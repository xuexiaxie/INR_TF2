/* -*- P4_16 -*- */
/*************************************************************************
 **************  E C M P   R O U T I N G   (I N G R E S S)  **************
 *************************************************************************
 * This file is included inside control SwitchIngress(...).
 * It provides: port_role, fabric_terminate, roce_ecmp, arp_terminate,
 * arp_ecmp tables and the apply block for pod2pod ECMP routing.
 *************************************************************************/

    action set_edge1()   { meta.role = role_t.EDGE1; }
    action set_edge2()   { meta.role = role_t.EDGE2; }
    action set_fabric_a(){ meta.role = role_t.FABRIC_A; }
    action set_fabric_b(){ meta.role = role_t.FABRIC_B; }
    action nop(){}
    action drop(bit<3> drop_bits) { ig_intr_md_for_dprsr.drop_ctl = drop_bits; }
    action ecmp_forward(PortId_t port) {
        ig_intr_md_for_tm.ucast_egress_port = port;
    }
    action forward(PortId_t port) {
        ig_intr_md_for_tm.ucast_egress_port = port;
    }

    table port_role {
        key = {
            ig_intr_md.ingress_port : exact;
        }
        actions = {
            set_edge1;
            set_edge2;
            set_fabric_a;
            set_fabric_b;
        }
        size = 64;
    }

    table fabric_terminate {
        key = {
            meta.role        : exact;
            hdr.ipv4.dst_addr: exact;
        }
        actions = {
            forward;
            @defaultonly nop;
        }
        size = 64;
    }

    Hash<bit<16>>(HashAlgorithm_t.CRC16) ecmp_hash;
    ActionProfile(2048) ecmp_ap;
    ActionSelector(
        ecmp_ap,
        ecmp_hash,
        SelectorMode_t.FAIR,
        64,   // max group size
        16    // max groups
    ) ecmp_selector;

    Hash<bit<16>>(HashAlgorithm_t.CRC16) arp_hash;
    ActionProfile(2048) arp_ap;
    ActionSelector(
        arp_ap,
        arp_hash,
        SelectorMode_t.FAIR,
        64,   // max group size
        16    // max groups
    ) arp_selector;

    table roce_ecmp {
        key = {
            ig_intr_md.ingress_port : exact;
            hdr.ipv4.src_addr : selector;
            hdr.ipv4.dst_addr : selector;
            hdr.udp.src_port  : selector;
            hdr.udp.dst_port  : selector;
            hdr.bth.destination_qp : selector;
        }
        actions = {
            ecmp_forward;
            @defaultonly nop;
        }
        implementation = ecmp_selector;
        size = 1024;
    }

    table arp_terminate {
        key = {
            meta.role              : exact;
            hdr.arp.target_ip_addr : exact;
        }
        actions = {
            forward;
            @defaultonly nop;
        }
        size = 64;
    }

    table arp_ecmp {
        key = {
            ig_intr_md.ingress_port     : exact;
            hdr.arp.sender_ip_addr      : selector;
            hdr.arp.target_ip_addr      : selector;
        }
        actions = {
            ecmp_forward;
            @defaultonly nop;
        }
        implementation = arp_selector;
        size = 64;
    }

    apply {
        /* ----- initialize TM metadata ----- */
        ig_intr_md_for_tm.ucast_egress_port = 0;
        ig_intr_md_for_tm.mcast_grp_a = 0;
        ig_intr_md_for_tm.rid = 0;
        meta.role = role_t.FABRIC_A;

        port_role.apply();

        if (hdr.ethernet.ether_type == (bit<16>) ether_type_t.ARP) {
            if (meta.role == role_t.EDGE1 || meta.role == role_t.EDGE2) {
                arp_ecmp.apply();
            } else {
                arp_terminate.apply();
            }
        } else {
            if (meta.role == role_t.EDGE1 || meta.role == role_t.EDGE2) {
                roce_ecmp.apply();
            } else {
                fabric_terminate.apply();
            }
        }
    }
