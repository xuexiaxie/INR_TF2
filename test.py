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

        # ARP fixed path: edge ARP always uses 184-320 (unchanged when RoCE ECMP is updated)
        ARP_FIXED_PORT_GRP1 = 194
        ARP_FIXED_PORT_GRP2 = 314
        arp_fixed_path_tbl = bfrt_info.table_get("SwitchIngress.arp_fixed_path")
        arp_fixed_path_tbl.entry_add(
            target,
            [arp_fixed_path_tbl.make_key([
                gc.KeyTuple('ig_intr_md.ingress_port', port_src) #136
            ])],
            [arp_fixed_path_tbl.make_data(
                [gc.DataTuple('port', ARP_FIXED_PORT_GRP1)], #194
                'SwitchIngress.forward'
            )]
        )
        arp_fixed_path_tbl.entry_add(
            target,
            [arp_fixed_path_tbl.make_key([
                gc.KeyTuple('ig_intr_md.ingress_port', ARP_FIXED_PORT_GRP2) #314
            ])],
            [arp_fixed_path_tbl.make_data(
                [gc.DataTuple('port', port_dst)], #304
                'SwitchIngress.forward'
            )]
        )
        arp_fixed_path_tbl.entry_add(
            target,
            [arp_fixed_path_tbl.make_key([
                gc.KeyTuple('ig_intr_md.ingress_port', port_dst) #304
            ])],
            [arp_fixed_path_tbl.make_data(
                [gc.DataTuple('port', ARP_FIXED_PORT_GRP2)], #314
                'SwitchIngress.forward'
            )]
        )
        arp_fixed_path_tbl.entry_add(
            target,
            [arp_fixed_path_tbl.make_key([
                gc.KeyTuple('ig_intr_md.ingress_port', ARP_FIXED_PORT_GRP1) #194
            ])],
            [arp_fixed_path_tbl.make_data(
                [gc.DataTuple('port', port_src)], #136
                'SwitchIngress.forward'
            )]
        )
        logger.info("ecmp + arp configured OK .")

        # ====================================================================
        # RECONFIGURATION: replace ports 192,193 -> 168,169  (grp1)
        #                            312,313 -> 296,297  (grp2)
        # Pre-add new members BEFORE the trigger so the actual switch is atomic
        # ====================================================================
        new_ports_grp1 = [168, 169]   # replacing 192, 193
        new_ports_grp2 = [296, 297]   # replacing 312, 313

        new_grp1_member_ids = []
        new_grp2_member_ids = []
        mid = member_id   # continues from where member_id left off (= 17)

        ap = bfrt_info.table_get("SwitchIngress.ecmp_ap")
        for p in new_ports_grp1:
            ap.entry_add(target,
                [ap.make_key([gc.KeyTuple('$ACTION_MEMBER_ID', mid)])],
                [ap.make_data([gc.DataTuple('port', p)], 'SwitchIngress.ecmp_forward')]
            )
            new_grp1_member_ids.append(mid)
            mid += 1
        for p in new_ports_grp2:
            ap.entry_add(target,
                [ap.make_key([gc.KeyTuple('$ACTION_MEMBER_ID', mid)])],
                [ap.make_data([gc.DataTuple('port', p)], 'SwitchIngress.ecmp_forward')]
            )
            new_grp2_member_ids.append(mid)
            mid += 1

        for p in new_ports_grp1:
            port_role.entry_add(
                target,
                [port_role.make_key([gc.KeyTuple('ig_intr_md.ingress_port', p)])],
                [port_role.make_data([], 'SwitchIngress.set_fabric_a')]
            )

        for p in new_ports_grp2:
            port_role.entry_add(
                target,
                [port_role.make_key([gc.KeyTuple('ig_intr_md.ingress_port', p)])],
                [port_role.make_data([], 'SwitchIngress.set_fabric_b')]
            )

        logger.info("New ECMP members pre-added. Waiting for T_trigger ...")

        # ====================================================================
        # TRIGGER: wait T seconds then atomically switch to new ECMP members
        # Set T_trigger to the same wall-clock offset used by rdma_sender
        # (both scripts should be started at the same time; sender starts
        #  at its own T=0 aligned with base_trace_t in the trace file)
        # ====================================================================
        import time
        T_trigger = 3.0  # seconds after this script starts
        time.sleep(T_trigger)

        # Build updated group member-id lists:
        # grp1: keep ids 3..8 (ports 194,195,184,185,186,187), swap ids 1,2 -> new
        # grp1_member_ids = [1,2,3,4,5,6,7,8]  (192,193,194,195,184,185,186,187)
        updated_grp1_ids    = new_grp1_member_ids[:2] + grp1_member_ids[2:]
        # grp2: keep ids 11..16 (314,315,320,321,322,323), swap ids 9,10 -> new
        # grp2_member_ids = [9,10,11,12,13,14,15,16]  (312,313,314,315,320,321,322,323)
        updated_grp2_ids    = new_grp2_member_ids[:2] + grp2_member_ids[2:]

        # ARP is only used when establishing the connection; data path uses roce_ecmp.
        selector = bfrt_info.table_get("SwitchIngress.ecmp_selector")
        selector.entry_mod(target,
            [selector.make_key([gc.KeyTuple('$SELECTOR_GROUP_ID', 1)])],
            [selector.make_data([
                gc.DataTuple('$MAX_GROUP_SIZE', 64),
                gc.DataTuple('$ACTION_MEMBER_ID', int_arr_val=updated_grp1_ids),
                gc.DataTuple('$ACTION_MEMBER_STATUS', bool_arr_val=[True]*len(updated_grp1_ids))
            ])]
        )
        selector.entry_mod(target,
            [selector.make_key([gc.KeyTuple('$SELECTOR_GROUP_ID', 2)])],
            [selector.make_data([
                gc.DataTuple('$MAX_GROUP_SIZE', 64),
                gc.DataTuple('$ACTION_MEMBER_ID', int_arr_val=updated_grp2_ids),
                gc.DataTuple('$ACTION_MEMBER_STATUS', bool_arr_val=[True]*len(updated_grp2_ids))
            ])]
        )

        logger.info("pod2pod ECMP reconfigured at T=%.6f (192,193->168,169 / 312,313->296,297)" % time.time())
