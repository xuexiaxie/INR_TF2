/* -*- P4_16 -*- */

#include <core.p4>
#if __TARGET_TOFINO__ == 2
#include <t2na.p4>
#else
#include <tna.p4>
#endif

/*************************************************************************
 ************* C O N S T A N T S    A N D   T Y P E S  *******************
 **************************************************************************/


/**
 * @brief Basic networking
 */
typedef bit<48> mac_addr_t;
typedef bit<32> ipv4_addr_t;
typedef bit<8> ip_protocol_t;
const ip_protocol_t IP_PROTOCOL_UDP = 0x11;
const ip_protocol_t IP_PROTOCOL_TCP = 0x6;
const int MCAST_GRP_ID = 1;

enum bit<16> ether_type_t {
    IPV4 = 0x0800,
    ARP = 0x0806,
    ETHERTYPE_AFC = 0x2001
}
enum bit<8> ipv4_proto_t {
    TCP = IP_PROTOCOL_TCP,
    UDP = IP_PROTOCOL_UDP
}

const bit<16> UDP_ROCE_V2 = 4791;  // UDP RoCEv2

/*************************************************************************
 ***********************  H E A D E R S  *********************************
 *************************************************************************/

/*  Define all the headers the program will recognize             */
/*  The actual sets of headers processed by each gress can differ */

/* Standard ethernet header */
header ethernet_h {
    mac_addr_t dst_addr;
    mac_addr_t src_addr;
    bit<16> ether_type;
}

header arp_h {
    bit<16> htype;
    bit<16> ptype;
    bit<8> hlen;
    bit<8> plen;
    bit<16> oper;
    mac_addr_t sender_hw_addr;
    ipv4_addr_t sender_ip_addr;
    mac_addr_t target_hw_addr;
    ipv4_addr_t target_ip_addr;
}

header ipv4_h {
    bit<4> version;
    bit<4> ihl;
    bit<6> dscp;
    bit<2> ecn;
    bit<16> total_len;
    bit<16> identification;
    bit<3> flags;
    bit<13> frag_offset;
    bit<8> ttl;
    bit<8> protocol;
    bit<16> hdr_checksum;
    ipv4_addr_t src_addr;
    ipv4_addr_t dst_addr;
}

header tcp_h {
    bit<16> src_port;
    bit<16> dst_port;
    bit<32> seq_no;
    bit<32> ack_no;
    bit<4> data_offset;
    bit<4> res;
    bit<8> flags;
    bit<16> window;
    bit<16> checksum;
    bit<16> urgent_ptr;
}

header udp_h {
    bit<16> src_port;
    bit<16> dst_port;
    bit<16> hdr_length;
    bit<16> checksum;
}

/**
 * @brief RoCEv2 headers
 */

header ib_bth_h {
    bit<8> opcode;
    bit<8> flags;  // 1 bit solicited event, 1 bit migreq, 2 bit padcount, 4 bit headerversion
    bit<16> partition_key;
    bit<8> reserved0;
    bit<24> destination_qp;
    bit<1> ack_request;
    bit<7> reserved1;
    bit<24> packet_seqnum;
}


header adv_flow_ctl_h {
    bit<32> adv_flow_ctl;

    /** 32-bit adv_flow_ctl format */
    // bit<1> qfc;
    // bit<2> tm_pipe_id;
    // bit<4> tm_mac_id;
    // bit<3> _pad;
    // bit<7> tm_mac_qid;
    // bit<15> credit; 
}


/***********************  H E A D E R S  ************************/

struct header_t {
    ethernet_h ethernet;
    adv_flow_ctl_h afc_msg;
    ipv4_h ipv4;
    arp_h arp;
    tcp_h tcp;
    udp_h udp;
    ib_bth_h bth;
}

/******  G L O B A L   I N G R E S S   M E T A D A T A  *********/
enum bit<2> role_t {
    EDGE1 = 0,
    EDGE2 = 1,
    FABRIC_A = 3,
    FABRIC_B = 2
}

struct metadata_t {
    bit<32> where_to_afc;
    PortId_t eg_port;
    bit<1> eg_bypass;
    role_t role;
}



/*************************************************************************
 **************  I N G R E S S   P R O C E S S I N G   *******************
 *************************************************************************/

/***********************  P A R S E R  **************************/
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





/***************** M A T C H - A C T I O N  *********************/

control SwitchIngress(
    /* User */
    inout header_t hdr,
    inout metadata_t meta,
    /* Intrinsic */
    in ingress_intrinsic_metadata_t ig_intr_md,
    in ingress_intrinsic_metadata_from_parser_t ig_intr_md_from_prsr,
    inout ingress_intrinsic_metadata_for_deparser_t ig_intr_md_for_dprsr,
    inout ingress_intrinsic_metadata_for_tm_t ig_intr_md_for_tm) {

    action set_edge1()   { meta.role = role_t.EDGE1; } //从host1出发
    action set_edge2()   { meta.role = role_t.EDGE2; } //从host2出发
    action set_fabric_a(){ meta.role = role_t.FABRIC_A; }//到host1
    action set_fabric_b(){ meta.role = role_t.FABRIC_B; }//到host2
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

    // ARP 用的独立 ECMP selector
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
            meta.role              : exact;    // FABRIC_A / FABRIC_B
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
            ig_intr_md.ingress_port     : exact;    // 136 或 304
            hdr.arp.sender_ip_addr      : selector; // 参与 hash，增加熵
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

        if(hdr.ethernet.ether_type == (bit<16>) ether_type_t.ARP){
			// do the broadcast to all involved ports
			if (meta.role == role_t.EDGE1 || meta.role == role_t.EDGE2) {
                arp_ecmp.apply();
            } else {
                arp_terminate.apply();
            }
		} else {
            if (meta.role == role_t.EDGE1 || meta.role == role_t.EDGE2) {
                roce_ecmp.apply();
            }
            else {
                fabric_terminate.apply();
            }
        }
    }
}

/*********************  D E P A R S E R  ************************/

control SwitchIngressDeparser(packet_out pkt,
                        /* User */
                        inout header_t hdr,
                        in metadata_t meta,
                        /* Intrinsic */
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
 ****************  E G R E S S   P R O C E S S I N G   *******************
 *************************************************************************/


    /***********************  P A R S E R  **************************/

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

    /***************** M A T C H - A C T I O N  *********************/

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

    /*********************  D E P A R S E R  ************************/

control SwitchEgressDeparser(packet_out pkt,
    /* User */
    inout header_t                       hdr,
    in    metadata_t                      meta,
    /* Intrinsic */
    in egress_intrinsic_metadata_for_deparser_t eg_intr_md_for_dprsr,
    in egress_intrinsic_metadata_t eg_intr_md,
    in egress_intrinsic_metadata_from_parser_t eg_intr_md_from_prsr){

    Checksum() ipv4_checksum;

	apply{
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


/************ F I N A L   P A C K A G E ******************************/
Pipeline(
    SwitchIngressParser(),
    SwitchIngress(),
    SwitchIngressDeparser(),
    SwitchEgressParser(),
    SwitchEgress(),
    SwitchEgressDeparser()
) pipe;

Switch(pipe) main;