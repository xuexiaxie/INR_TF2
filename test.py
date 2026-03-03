import logging
from bfruntime_client_base_tests import BfRuntimeTest
import bfrt_grpc.client as gc
import ipaddress

logger = logging.getLogger('Test')
if not logger.handlers:
    logger.addHandler(logging.StreamHandler())

class TestQueueAFC(BfRuntimeTest):

    def setUp(self):
        client_id = 0
        p4_name = "pod2pod"  # 和你的 P4 程序名保持一致
        BfRuntimeTest.setUp(self, client_id, p4_name)

    def runTest(self):
        logger.info("=============== Testing Tofino2 ===============")

        pipe_id = 0xffff
        target = gc.Target(device_id=0, pipe_id=pipe_id)

        # 这个 bfrt_info 里既有 SwitchIngress.* 也有 $pre.*
        bfrt_info = self.interface.bfrt_info_get("pod2pod")
        port_src = 136
        port_dst = 304

        IP_HOST2 = int(ipaddress.IPv4Address("192.168.40.2"))
        IP_HOST1 = int(ipaddress.IPv4Address("192.168.40.3"))
        ports_grp1 = [192,193,194,195,184,185,186,187]
        ports_grp2 = [312,313,314,315,320,321,322,323]

        # -----------------------------
        # Step 0: 配置其他转发逻辑
        # -----------------------------
        port_role = bfrt_info.table_get("SwitchIngress.port_role")

        # EDGE ports
        port_role.entry_add(
            target,
            [port_role.make_key([
                gc.KeyTuple('ig_intr_md.ingress_port', port_src)
            ])],
            [port_role.make_data([], 'SwitchIngress.set_edge1')]
        )

        port_role.entry_add(
            target,
            [port_role.make_key([
                gc.KeyTuple('ig_intr_md.ingress_port', port_dst)
            ])],
            [port_role.make_data([], 'SwitchIngress.set_edge2')]
        )

        # 标记虚拟src tor的端口
        for p in ports_grp1:
            port_role.entry_add(
                target,
                [port_role.make_key([
                    gc.KeyTuple('ig_intr_md.ingress_port', p)
                ])],
                [port_role.make_data([], 'SwitchIngress.set_fabric_a')]
            )

        # 标记虚拟dst tor的端口
        for p in ports_grp2:
            port_role.entry_add(
                target,
                [port_role.make_key([
                    gc.KeyTuple('ig_intr_md.ingress_port', p)
                ])],
                [port_role.make_data([], 'SwitchIngress.set_fabric_b')]
            )

        fabric = bfrt_info.table_get("SwitchIngress.fabric_terminate")
        # FABRIC_A -> HOST1
        fabric.entry_add(
            target,
            [fabric.make_key([
                gc.KeyTuple('meta.role', 3),   # FABRIC_A
                gc.KeyTuple('hdr.ipv4.dst_addr', IP_HOST1)
            ])],
            [fabric.make_data(
                [gc.DataTuple('port', port_src)],
                'SwitchIngress.forward'
            )]
        )
        # FABRIC_B -> HOST2
        fabric.entry_add(
            target,
            [fabric.make_key([
                gc.KeyTuple('meta.role', 2),   # FABRIC_B
                gc.KeyTuple('hdr.ipv4.dst_addr', IP_HOST2)
            ])],
            [fabric.make_data(
                [gc.DataTuple('port', port_dst)],
                'SwitchIngress.forward'
            )]
        )
        # -----------------------------
        # Step 0: 配置简单 ECMP 转发表
        # -----------------------------
        ap = bfrt_info.table_get("SwitchIngress.ecmp_ap")
        grp1_member_ids = []
        grp2_member_ids = []
        member_id = 1 #从1开始分配内部id

        #-----------------group1 members ------------------
        for p in ports_grp1:
            ap.entry_add(
                target,
                [ap.make_key([
                    gc.KeyTuple('$ACTION_MEMBER_ID', member_id)
                ])],
                [ap.make_data(
                    [gc.DataTuple('port', p)],
                    'SwitchIngress.ecmp_forward'
                )]
            )
            grp1_member_ids.append(member_id)
            member_id += 1
        #-----------------group2 members ------------------
        for p in ports_grp2:
            ap.entry_add(
                target,
                [ap.make_key([
                    gc.KeyTuple('$ACTION_MEMBER_ID', member_id)
                ])],
                [ap.make_data(
                    [gc.DataTuple('port', p)],
                    'SwitchIngress.ecmp_forward'
                )]
            )
            grp2_member_ids.append(member_id)
            member_id += 1
        # =====================================
        # 创建selector groups
        # =====================================
        selector = bfrt_info.table_get("SwitchIngress.ecmp_selector")
        selector.entry_add(
            target,
            [selector.make_key([
                gc.KeyTuple('$SELECTOR_GROUP_ID', 1)
            ])],
            [selector.make_data([
                gc.DataTuple('$MAX_GROUP_SIZE', 64),

                gc.DataTuple('$ACTION_MEMBER_ID',
                            int_arr_val=grp1_member_ids),

                gc.DataTuple('$ACTION_MEMBER_STATUS',
                            bool_arr_val=[True]*len(grp1_member_ids))
            ])]
        )
        selector.entry_add(
            target,
            [selector.make_key([
                gc.KeyTuple('$SELECTOR_GROUP_ID', 2)
            ])],
            [selector.make_data([
                gc.DataTuple('$MAX_GROUP_SIZE', 64),

                gc.DataTuple(
                    '$ACTION_MEMBER_ID',
                    int_arr_val=grp2_member_ids
                ),

                gc.DataTuple(
                    '$ACTION_MEMBER_STATUS',
                    bool_arr_val=[True]*len(grp2_member_ids)
                )
            ])]
        )

        roce = bfrt_info.table_get("SwitchIngress.roce_ecmp")
        # ingress --> group1
        roce.entry_add(
            target,
            [roce.make_key([
                gc.KeyTuple('ig_intr_md.ingress_port', port_src)
            ])],
            [roce.make_data([
                gc.DataTuple('$SELECTOR_GROUP_ID', 1)
            ])]
        )
        # ingress --> group2
        roce.entry_add(
            target,
            [roce.make_key([
                gc.KeyTuple('ig_intr_md.ingress_port', port_dst)
            ])],
            [roce.make_data([
                gc.DataTuple('$SELECTOR_GROUP_ID', 2)
            ])]
        )

        # -----------------------------
        # Step 1: 配置 PRE 组播表项（ARP 用 mgid=1 flood）
        # -----------------------------
        flood_ports = [port_src, port_dst] + ports_grp1 + ports_grp2 
        # 1) $pre.node：创建一个 L1 node，包含两个机器端口
        mcast_grp_a = 1       # 要和 P4 里的 MCAST_GRP_ID 一致
        l1_node_a   = 1       # L1 node id，随便选，只要一致
        rid         = 0       # 和 ig_intr_md_for_tm.rid 对齐即可

        l2_node_ports = flood_ports  # 需要 flood 的 dev_port 列表
        l2_node_lags  = []   # 不用 LAG 就留空

        mgid_table = bfrt_info.table_get("$pre.mgid")
        node_table = bfrt_info.table_get("$pre.node")

        # 先添加 MGID 条目（只加 key，就像你参考代码里的做法）
        logger.info("Adding MGID table entry for mgid=%d" % mcast_grp_a)
        mgid_table.entry_add(
            target,
            [mgid_table.make_key([
                gc.KeyTuple('$MGID', mcast_grp_a)
            ])]
        )

        # 再添加 node（L1 node），绑定端口列表
        logger.info("Adding MC node table entry for node_id=%d" % l1_node_a)
        node_table.entry_add(
            target,
            [node_table.make_key([
                gc.KeyTuple('$MULTICAST_NODE_ID', l1_node_a)
            ])],
            [node_table.make_data([
                gc.DataTuple('$MULTICAST_RID', rid),
                gc.DataTuple('$MULTICAST_LAG_ID', int_arr_val=l2_node_lags),
                gc.DataTuple('$DEV_PORT',
                        int_arr_val=[int(p) for p in l2_node_ports])
            ])]
        )

        # 最后用 entry_mod 把 MGID 关联到这个 L1 node 上
        logger.info("Associating mgid=%d with node_id=%d" % (mcast_grp_a, l1_node_a))
        mgid_table.entry_mod(
            target,
            [mgid_table.make_key([
                gc.KeyTuple('$MGID', mcast_grp_a)
            ])],
            [mgid_table.make_data([
                gc.DataTuple('$MULTICAST_NODE_ID',           int_arr_val=[l1_node_a]),
                gc.DataTuple('$MULTICAST_NODE_L1_XID_VALID', bool_arr_val=[0]),
                gc.DataTuple('$MULTICAST_NODE_L1_XID',       int_arr_val=[0])
            ])]
        )


        logger.info("ecmp + arp configured OK.")
