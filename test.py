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

        IP_HOST2 = int(ipaddress.IPv4Address("192.168.41.2"))
        IP_HOST1 = int(ipaddress.IPv4Address("192.168.41.3"))
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

        arp_term = bfrt_info.table_get("SwitchIngress.arp_terminate")
        # FABRIC_A (ports_grp1 ingress) -> host1 (192.168.41.3 via port 136)
        arp_term.entry_add(
            target,
            [arp_term.make_key([
                gc.KeyTuple('meta.role', 3),   # FABRIC_A
                gc.KeyTuple('hdr.arp.target_ip_addr', IP_HOST1)  # 192.168.41.3
            ])],
            [arp_term.make_data(
                [gc.DataTuple('port', port_src)],   # 136
                'SwitchIngress.forward'
            )]
        )

        # FABRIC_B (ports_grp2 ingress) -> host2 (192.168.41.2 via port 304)
        arp_term.entry_add(
            target,
            [arp_term.make_key([
                gc.KeyTuple('meta.role', 2),   # FABRIC_B
                gc.KeyTuple('hdr.arp.target_ip_addr', IP_HOST2)  # 192.168.41.2
            ])],
            [arp_term.make_data(
                [gc.DataTuple('port', port_dst)],   # 304
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
        # Step 0: 配置简单 ECMP 转发表
        # -----------------------------
        ap = bfrt_info.table_get("SwitchIngress.arp_ap")
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
        arp_selector = bfrt_info.table_get("SwitchIngress.arp_selector")
        arp_selector.entry_add(
            target,
            [arp_selector.make_key([
                gc.KeyTuple('$SELECTOR_GROUP_ID', 1)
            ])],
            [arp_selector.make_data([
                gc.DataTuple('$MAX_GROUP_SIZE', 64),

                gc.DataTuple('$ACTION_MEMBER_ID',
                            int_arr_val=grp1_member_ids),

                gc.DataTuple('$ACTION_MEMBER_STATUS',
                            bool_arr_val=[True]*len(grp1_member_ids))
            ])]
        )
        arp_selector.entry_add(
            target,
            [arp_selector.make_key([
                gc.KeyTuple('$SELECTOR_GROUP_ID', 2)
            ])],
            [arp_selector.make_data([
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

        arp_ecmp_tbl = bfrt_info.table_get("SwitchIngress.arp_ecmp")
        # ARP 从 136 进来：在 ports_grp1 上 ECMP
        arp_ecmp_tbl.entry_add(
            target,
            [arp_ecmp_tbl.make_key([
                gc.KeyTuple('ig_intr_md.ingress_port', port_src)  # 136
            ])],
            [arp_ecmp_tbl.make_data([
                gc.DataTuple('$SELECTOR_GROUP_ID', 1)  # 同 group1
            ])]
        )

        # ARP 从 304 进来：在 ports_grp2 上 ECMP
        arp_ecmp_tbl.entry_add(
            target,
            [arp_ecmp_tbl.make_key([
                gc.KeyTuple('ig_intr_md.ingress_port', port_dst)  # 304
            ])],
            [arp_ecmp_tbl.make_data([
                gc.DataTuple('$SELECTOR_GROUP_ID', 2)  # 同 group2
            ])]
        )



        logger.info("ecmp + arp configured OK.")
