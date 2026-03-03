/* -*- P4_16 -*- */
/*************************************************************************
 ***********************  I N G R E S S   P A R S E R  *******************
 *************************************************************************/

parser SwitchIngressParser(packet_in pkt,
                out header_t hdr,
                out metadata_t meta,
                out ingress_intrinsic_metadata_t ig_intr_md,
                out ingress_intrinsic_metadata_for_tm_t ig_intr_md_for_tm,
                out ingress_intrinsic_metadata_from_parser_t ig_intr_md_from_prsr){
    /* This is a mandatory state, required by Tofino Architecture */
    state start {
        pkt.extract(ig_intr_md);
        pkt.advance(PORT_METADATA_SIZE);  // macro defined in tofino.p4
        transition parse_ethernet;
    }

    state parse_ethernet {
        pkt.extract(hdr.ethernet);
        transition select(hdr.ethernet.ether_type){
            (bit<16>)ether_type_t.IPV4: parse_ipv4;
            (bit<16>)ether_type_t.ARP: parse_arp;
            (bit<16>)ether_type_t.ETHERTYPE_AFC : parse_afc;
            default: accept;
        }
    }

    state parse_ipv4 {
        pkt.extract(hdr.ipv4);
        transition select(hdr.ipv4.protocol) {
            (bit<8>)ipv4_proto_t.TCP : parse_tcp;
            (bit<8>)ipv4_proto_t.UDP : parse_udp;
            default: accept;
        }
    }

    state parse_afc {
        pkt.extract(hdr.afc_msg);
        transition accept;
    }

    state parse_arp {
        pkt.extract(hdr.arp);
        transition accept;
    }

    state parse_tcp {
        pkt.extract(hdr.tcp);
        transition accept;
    }

    state parse_udp {
        pkt.extract(hdr.udp);
        transition select(hdr.udp.dst_port) {
            UDP_ROCE_V2: parse_bth;
            default: accept;
        }
    }

    state parse_bth {
        pkt.extract(hdr.bth);
        transition accept;
    }
}

/*************************************************************************
 *********************  I N G R E S S   D E P A R S E R  *****************
 *************************************************************************/

control SwitchIngressDeparser(packet_out pkt,
                        inout header_t hdr,
                        in metadata_t meta,
                        in ingress_intrinsic_metadata_for_deparser_t ig_dprsr_md) {

    Checksum() ipv4_checksum;

    apply {
        hdr.ipv4.hdr_checksum = ipv4_checksum.update({
            hdr.ipv4.version,
            hdr.ipv4.ihl,
            hdr.ipv4.dscp,
            hdr.ipv4.ecn,
            hdr.ipv4.total_len,
            hdr.ipv4.identification,
            hdr.ipv4.flags,
            hdr.ipv4.frag_offset,
            hdr.ipv4.ttl,
            hdr.ipv4.protocol,
            hdr.ipv4.src_addr,
            hdr.ipv4.dst_addr});

        pkt.emit(hdr);
    }
}

/*************************************************************************
 ***********************  E G R E S S   P A R S E R  *********************
 *************************************************************************/

parser SwitchEgressParser(packet_in pkt,
    out header_t hdr,
    out metadata_t meta,
    out egress_intrinsic_metadata_t eg_intr_md,
    out egress_intrinsic_metadata_from_parser_t eg_intr_md_from_prsr){

    /* This is a mandatory state, required by Tofino Architecture */
    state start {
        pkt.extract(eg_intr_md);
        transition parse_ethernet;
    }

    state parse_ethernet {
        pkt.extract(hdr.ethernet);
        transition select(hdr.ethernet.ether_type) {
            (bit<16>)ether_type_t.IPV4 : parse_ipv4;
            (bit<16>)ether_type_t.ARP : parse_arp;
            (bit<16>)ether_type_t.ETHERTYPE_AFC : parse_afc;
            default: accept;
        }
    }

    state parse_ipv4 {
        pkt.extract(hdr.ipv4);
        transition select(hdr.ipv4.protocol) {
            (bit<8>)ipv4_proto_t.TCP : parse_tcp;
            (bit<8>)ipv4_proto_t.UDP : parse_udp;
            default: accept;
        }
    }

    state parse_afc {
        pkt.extract(hdr.afc_msg);
        transition accept;
    }

    state parse_arp {
        pkt.extract(hdr.arp);
        transition accept;
    }

    state parse_tcp {
        pkt.extract(hdr.tcp);
        transition accept;
    }

    state parse_udp {
        pkt.extract(hdr.udp);
        transition select(hdr.udp.dst_port) {
            UDP_ROCE_V2: parse_bth;
            default: accept;
        }
    }

    state parse_bth {
        pkt.extract(hdr.bth);
        transition accept;
    }
}

/*************************************************************************
 *********************  E G R E S S   D E P A R S E R  *******************
 *************************************************************************/

control SwitchEgressDeparser(packet_out pkt,
    inout header_t                       hdr,
    in    metadata_t                     meta,
    in egress_intrinsic_metadata_for_deparser_t eg_intr_md_for_dprsr,
    in egress_intrinsic_metadata_t eg_intr_md,
    in egress_intrinsic_metadata_from_parser_t eg_intr_md_from_prsr){

    Checksum() ipv4_checksum;

    apply {
        hdr.ipv4.hdr_checksum = ipv4_checksum.update({
            hdr.ipv4.version,
            hdr.ipv4.ihl,
            hdr.ipv4.dscp,
            hdr.ipv4.ecn,
            hdr.ipv4.total_len,
            hdr.ipv4.identification,
            hdr.ipv4.flags,
            hdr.ipv4.frag_offset,
            hdr.ipv4.ttl,
            hdr.ipv4.protocol,
            hdr.ipv4.src_addr,
            hdr.ipv4.dst_addr});

        pkt.emit(hdr);
    }
}
