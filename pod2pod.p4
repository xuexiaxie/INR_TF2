/* -*- P4_16 -*- */
/**
 * pod2pod - modular main program
 * Includes: base_headers, base_parsers, ecmp_routing.
 * DFM modules (dfm_source_migration, dfm_dest_inr, dfm_control_msg) to be added later.
 */

#include <core.p4>
#if __TARGET_TOFINO__ == 2
#include <t2na.p4>
#else
#include <tna.p4>
#endif

#include "base_headers.p4"
#include "base_parsers.p4"

/*************************************************************************
 **************  I N G R E S S   C O N T R O L  ***************************
 *************************************************************************/

control SwitchIngress(
    inout header_t hdr,
    inout metadata_t meta,
    in ingress_intrinsic_metadata_t ig_intr_md,
    in ingress_intrinsic_metadata_from_parser_t ig_intr_md_from_prsr,
    inout ingress_intrinsic_metadata_for_deparser_t ig_intr_md_for_dprsr,
    inout ingress_intrinsic_metadata_for_tm_t ig_intr_md_for_tm) {

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

    /* ARP fixed path: edge -> fabric on a single link (136-184-320-304) to avoid CQE errors when RoCE ECMP is updated */
    table arp_fixed_path {
        key = {
            ig_intr_md.ingress_port : exact;
        }
        actions = {
            forward;
            @defaultonly nop;
        }
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
            arp_fixed_path.apply();  
        } else {
            if (meta.role == role_t.EDGE1 || meta.role == role_t.EDGE2) {
                roce_ecmp.apply();
            } else {
                fabric_terminate.apply();
            }
        }
    }

}

/*************************************************************************
 ****************  E G R E S S   C O N T R O L  ***************************
 *************************************************************************/

control SwitchEgress(
    inout header_t hdr,
    inout metadata_t meta,
    in egress_intrinsic_metadata_t eg_intr_md,
    in egress_intrinsic_metadata_from_parser_t eg_intr_md_from_prsr,
    inout egress_intrinsic_metadata_for_deparser_t eg_intr_md_for_dprsr,
    inout egress_intrinsic_metadata_for_output_port_t eg_intr_md_for_oport) {

    apply {
    }
}

/*************************************************************************
 **************  P I P E L I N E   A N D   S W I T C H  *******************
 *************************************************************************/

Pipeline(
    SwitchIngressParser(),
    SwitchIngress(),
    SwitchIngressDeparser(),
    SwitchEgressParser(),
    SwitchEgress(),
    SwitchEgressDeparser()
) pipe;

Switch(pipe) main;
