/* -*- P4_16 -*- */
#ifndef _POD2POD_BASE_HEADERS_P4_
#define _POD2POD_BASE_HEADERS_P4_

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

#endif /* _POD2POD_BASE_HEADERS_P4_ */
