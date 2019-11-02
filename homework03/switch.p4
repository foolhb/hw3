/* -*- P4_16 -*- */
#include <core.p4>
#include <v1model.p4>

const bit<16> TYPE_IPV4 = 0x800;

/*************************************************************************
*********************** H E A D E R S  ***********************************
*************************************************************************/

typedef bit<9>  egressSpec_t;
typedef bit<48> macAddr_t;
typedef bit<32> ip4Addr_t;

header ethernet_t {
    macAddr_t dstAddr;
    macAddr_t srcAddr;
    bit<16>   etherType;
}

header myTunnel_t {
    bit<16> proto_id;
    bit<16> dst_id;
}

header tcp_t {
    bit<16>   srcPort;
    bit<16>   destPort;
    bit<32>   seqNum;
    bit<32>   ackNum;
    bit<4>    dataOffset;
    bit<3>    reserved;
    bit<1>    ns;
    bit<1>    cwr;
    bit<1>    ece;
    bit<1>    urg;
    bit<1>    ack;
    bit<1>    psh;
    bit<1>    pst;
    bit<1>    syn;
    bit<1>    fin;
    bit<16>   windowSize;
    bit<16>   checkSum;
    bit<16>   urgentPtr;
}

header udp_t {
    bit<16>   srcPort;
    bit<16>   destPort;
    bit<16>   length;
    bit<16>   checksum;
}

header ipv4_t {
    bit<4>    version;
    bit<4>    ihl;
    bit<8>    diffserv;
    bit<16>   totalLen;
    bit<16>   identification;
    bit<3>    flags;
    bit<13>   fragOffset;
    bit<8>    ttl;
    bit<8>    protocol;
    bit<16>   hdrChecksum;
    ip4Addr_t srcAddr;
    ip4Addr_t dstAddr;
}

struct metadata {
    /* empty */
}

struct headers {
    ethernet_t   ethernet;
    ipv4_t       ipv4;
    udp_t udp;
    tcp_t tcp;
}

/*************************************************************************
*********************** P A R S E R  ***********************************
*************************************************************************/

parser MyParser(packet_in packet,
                out headers hdr,
                inout metadata meta,
                inout standard_metadata_t standard_metadata) {

    state start {
        transition parse_ethernet;
    }

    state parse_ethernet {
        packet.extract(hdr.ethernet);
        transition select(hdr.ethernet.etherType) {
            TYPE_IPV4: parse_ipv4;
            default: accept;
        }
    }

    state parse_ipv4 {
        packet.extract(hdr.ipv4);
        transition accept;
    }

}

/*************************************************************************
************   C H E C K S U M    V E R I F I C A T I O N   *************
*************************************************************************/

control MyVerifyChecksum(inout headers hdr, inout metadata meta) {   
    apply {
	verify_checksum(
	    true,
            { hdr.ipv4.version,
	      hdr.ipv4.ihl,
              hdr.ipv4.diffserv,
              hdr.ipv4.totalLen,
              hdr.ipv4.identification,
              hdr.ipv4.flags,
              hdr.ipv4.fragOffset,
              hdr.ipv4.ttl,
              hdr.ipv4.protocol,
              hdr.ipv4.srcAddr,
              hdr.ipv4.dstAddr },
            hdr.ipv4.hdrChecksum,
            HashAlgorithm.csum16);
    }
}


/*************************************************************************
**************  I N G R E S S   P R O C E S S I N G   *******************
*************************************************************************/

control MyIngress(inout headers hdr,
                  inout metadata meta,
                  inout standard_metadata_t standard_metadata) {

    action drop() {
        mark_to_drop(standard_metadata);
    }
    
    action ipv4_forward(egressSpec_t port) {
        standard_metadata.egress_spec = port;
        hdr.ipv4.ttl = hdr.ipv4.ttl - 1;
    }

    table ipv4_lpm {
        key = {
            hdr.ipv4.dstAddr: lpm;
        }
        actions = {
            ipv4_forward;
            drop;
            NoAction;
        }
        size = 1024;
        default_action = NoAction();
    }

    table acl {
        key = {
            hdr.ethernet.dstAddr: ternary;
            hdr.ethernet.srcAddr: ternary;
            hdr.ipv4.srcAddr: ternary;
            hdr.ipv4.dstAddr: ternary;
            hdr.tcp.srcPort: ternary;
            hdr.tcp.destPort: ternary;
            hdr.udp.srcPort: ternary;
            hdr.udp.destPort: ternary;
        }
        actions = {
            drop;
            NoAction;
        }

        size = 1024;
        default_action = NoAction();

    }
    
    apply {
        // Process only IPv4 packets.
        if (hdr.ipv4.isValid() && standard_metadata.checksum_error == 0) {
        // Check if it's a package to the fictious via host 1. If true, hash the header and re-route
            if(hdr.ipv4.srcAddr == 0x0a00010b && hdr.ethernet.srcAddr == 0x080000000111 && hdr.ipv4.destAddr == 0x0a000063){
                bit<1> x;
                hash(x, HashAlgorithm.crc16, 0, { hdr.ipv4.dstAddr, hdr.ipv4.srcAddr, hdr.ethernet.srcAddr, hdr.ethernet.dstAddr }, 2);
                if (x == 0){
                // Modify the destination address
                    hdr.ipv4.dstAddr = 0x0a000216;
                    hdr.ethernet.dstAddr = 0x080000000222;
                } else {
                    hdr.ipv4.dstAddr = 0x0a000321;
                    hdr.ethernet.dstAddr = 0x080000000333;
                }
            }
	    ipv4_lpm.apply();
	    acl.apply();
        } else {
	    drop();
	}
    }
}

/*************************************************************************
****************  E G R E S S   P R O C E S S I N G   *******************
*************************************************************************/

control MyEgress(inout headers hdr,
                 inout metadata meta,
                 inout standard_metadata_t standard_metadata) {
    apply {  }
}

/*************************************************************************
*************   C H E C K S U M    C O M P U T A T I O N   **************
*************************************************************************/

control MyComputeChecksum(inout headers  hdr, inout metadata meta) {
     apply {
	update_checksum(
	    true,
            { hdr.ipv4.version,
	      hdr.ipv4.ihl,
              hdr.ipv4.diffserv,
              hdr.ipv4.totalLen,
              hdr.ipv4.identification,
              hdr.ipv4.flags,
              hdr.ipv4.fragOffset,
              hdr.ipv4.ttl,
              hdr.ipv4.protocol,
              hdr.ipv4.srcAddr,
              hdr.ipv4.dstAddr },
            hdr.ipv4.hdrChecksum,
            HashAlgorithm.csum16);
    }
}

/*************************************************************************
***********************  D E P A R S E R  *******************************
*************************************************************************/

control MyDeparser(packet_out packet, in headers hdr) {
    apply {
        packet.emit(hdr.ethernet);
        packet.emit(hdr.ipv4);
        packet.emit(hdr.tcp);
        packet.emit(hdr.udp);
    }
}

/*************************************************************************
***********************  S W I T C H  *******************************
*************************************************************************/

V1Switch(
MyParser(),
MyVerifyChecksum(),
MyIngress(),
MyEgress(),
MyComputeChecksum(),
MyDeparser()
) main;
