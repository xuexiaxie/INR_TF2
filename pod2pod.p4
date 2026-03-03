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

#include "ecmp_routing.p4"
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
