# SNMP::Info::Layer3::BayRS
# $Id: BayRS.pm,v 1.25 2008/08/02 03:21:47 jeneric Exp $
#
# Copyright (c) 2008 Eric Miller
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#
#     * Redistributions of source code must retain the above copyright notice,
#       this list of conditions and the following disclaimer.
#     * Redistributions in binary form must reproduce the above copyright
#       notice, this list of conditions and the following disclaimer in the
#       documentation and/or other materials provided with the distribution.
#     * Neither the name of the University of California, Santa Cruz nor the
#       names of its contributors may be used to endorse or promote products
#       derived from this software without specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE
# LIABLE FOR # ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
# CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
# SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
# INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
# CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
# ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
# POSSIBILITY OF SUCH DAMAGE.

package SNMP::Info::Layer3::BayRS;

use strict;
use Exporter;
use SNMP::Info;
use SNMP::Info::Layer3;
use SNMP::Info::Bridge;

@SNMP::Info::Layer3::BayRS::ISA = qw/SNMP::Info SNMP::Info::Layer3
    SNMP::Info::Bridge Exporter/;
@SNMP::Info::Layer3::BayRS::EXPORT_OK = qw//;

use vars qw/$VERSION %GLOBALS %FUNCS %MIBS %MUNGE %MODEL_MAP
    %MODID_MAP %PROCID_MAP/;

$VERSION = '2.00';

%MIBS = (
    %SNMP::Info::MIBS,
    %SNMP::Info::Layer3::MIBS,
    %SNMP::Info::Bridge::MIBS,
    'Wellfleet-HARDWARE-MIB'        => 'wfHwBpIdOpt',
    'Wellfleet-OSPF-MIB'            => 'wfOspfRouterId',
    'Wellfleet-DOT1QTAG-CONFIG-MIB' => 'wfDot1qTagCfgVlanName',
    'Wellfleet-CSMACD-MIB'          => 'wfCSMACDCct',
    'Wellfleet-MODULE-MIB'          => 'wfHwModuleSlot',
);

%GLOBALS = (
    %SNMP::Info::GLOBALS,
    %SNMP::Info::Layer3::GLOBALS,
    %SNMP::Info::Bridge::GLOBALS,
    'bp_id'       => 'wfHwBpIdOpt',
    'bp_serial'   => 'wfHwBpSerialNumber',
    'ospf_rtr_id' => 'wfOspfRouterId',
);

%FUNCS = (
    %SNMP::Info::FUNCS,
    %SNMP::Info::Layer3::FUNCS,
    %SNMP::Info::Bridge::FUNCS,

    # From Wellfleet-CSMACD-MIB::wfCSMACDTable
    'wf_csmacd_cct'  => 'wfCSMACDCct',
    'wf_csmacd_slot' => 'wfCSMACDSlot',
    'wf_csmacd_conn' => 'wfCSMACDConnector',
    'wf_csmacd_mtu'  => 'wfCSMACDMtu',
    'wf_duplex'      => 'wfCSMACDLineCapability',
    'wf_csmacd_line' => 'wfCSMACDLineNumber',

    # From Wellfleet-CSMACD-MIB::wfCSMACDAutoNegTable
    'wf_auto' => 'wfCSMACDAutoNegSpeedSelect',

    # From Wellfleet-DOT1QTAG-CONFIG-MIB::wfDot1qTagConfigTable
    'wf_vlan_name'      => 'wfDot1qTagCfgVlanName',
    'wf_local_vlan_id'  => 'wfDot1qTagCfgLocalVlanId',
    'wf_global_vlan_id' => 'wfDot1qTagCfgGlobalVlanId',
    'wf_vlan_port'      => 'wfDot1qTagCfgPhysicalPortId',

    # From Wellfleet-HARDWARE-MIB::wfHwTable
    'wf_hw_slot'     => 'wfHwSlot',
    'wf_hw_mod_id'   => 'wfHwModIdOpt',
    'wf_hw_mod_rev'  => 'wfHwModRev',
    'wf_hw_mod_ser'  => 'wfHwModSerialNumber',
    'wf_hw_mobo_id'  => 'wfHwMotherBdIdOpt',
    'wf_hw_mobo_rev' => 'wfHwMotherBdRev',
    'wf_hw_mobo_ser' => 'wfHwMotherBdSerialNumber',
    'wf_hw_diag'     => 'wfHwDiagPromRev',
    'wf_hw_boot'     => 'wfHwBootPromRev',
    'wf_hw_mobo_mem' => 'wfHwMotherBdMemorySize',
    'wf_hw_cfg_time' => 'wfHwConfigDateAndTime',
    'wf_hw_db_ser'   => 'wfHwDaughterBdSerialNumber',
    'wf_hw_bb_ser'   => 'wfHwBabyBdSerialNumber',
    'wf_hw_mm_ser'   => 'wfHwModuleModSerialNumber',
    'wf_hw_md1_ser'  => 'wfHwModDaughterBd1SerialNumber',
    'wf_hw_md2_ser'  => 'wfHwModDaughterBd2SerialNumber',
);

%MUNGE = (
    %SNMP::Info::MUNGE,
    %SNMP::Info::Layer3::MUNGE,
    %SNMP::Info::Bridge::MUNGE,
    'wf_hw_boot'     => \&munge_hw_rev,
    'wf_hw_diag'     => \&munge_hw_rev,
    'wf_hw_mobo_ser' => \&munge_wf_serial,
    'wf_hw_mod_ser'  => \&munge_wf_serial,
    'wf_hw_db_ser'   => \&munge_wf_serial,
    'wf_hw_bb_ser'   => \&munge_wf_serial,
    'wf_hw_mm_ser'   => \&munge_wf_serial,
    'wf_hw_md1_ser'  => \&munge_wf_serial,
    'wf_hw_md2_ser'  => \&munge_wf_serial,
);

%MODEL_MAP = (
    'acefn'     => 'FN',
    'aceln'     => 'LN',
    'acecn'     => 'CN',
    'afn'       => 'AFN',
    'in'        => 'IN',
    'an'        => 'AN',
    'arn'       => 'ARN',
    'sys5000'   => '5000',
    'freln'     => 'BLN',
    'frecn'     => 'BCN',
    'frerbln'   => 'BLN-2',
    'asn'       => 'ASN',
    'asnzcable' => 'ASN-Z',
    'asnbcable' => 'ASN-B',
);

%MODID_MAP = (
    1   => 'DUAL ENET',
    8   => 'DUAL ENET',
    16  => 'QSYNC',
    24  => 'DUAL T1',
    32  => 'SSE,DSE',
    40  => 'TS 4/16 - 1x2',
    44  => 'TS 4/16 - 1x1',
    45  => 'TS 4/16 - 1x0',
    48  => 'SYSTEM I/O',
    49  => 'SYSTEM I/O',
    56  => 'DUAL T1',
    57  => 'DUAL T1 - 56K',
    58  => 'T1 - SINGLE PORT',
    60  => 'T1 56K - SINGLE PORT',
    61  => 'E1 - 75 OHM',
    80  => 'QSYNC',
    112 => 'DSDE 4',
    116 => 'DSE',
    118 => 'SSE',
    132 => 'ESA 2x0',
    156 => 'ESA 2x2',
    162 => 'QUAD ENET with CAM DAUGHTERCARD',
    164 => 'QUAD ENET with CAM DAUGHTERCARD,QUAD ENET CAM DAUGHTER CARD',
    168 => 'MCT1 - 2',
    169 => 'MCT1 - 1',
    176 => 'DUAL TOKEN',
    184 => 'MCE1 - DUAL PORT',
    185 => 'MCE1 - SINGLE PORT',
    192 => 'MULTIMODE FDDI',
    193 => 'SINGLEMODE FDDI PHY-B',
    194 => 'SINGLEMODE FDDI PHY-A/B',
    195 => 'SINGLEMODE FDDI PHY-A',
    196 => 'MULTIMODE FDDI,FDDI CAM DAUGHTER CARD',
    197 => 'SINGLEMODE FDDI PHY-B,FDDI CAM DAUGHTER CARD',
    198 => 'SINGLEMODE FDDI PHY-A/B,FDDI CAM DAUGHTER CARD',
    199 => 'SINGLEMODE FDDI PHY-A,FDDI CAM DAUGHTER CARD',
    208 => {
        0 =>
            'AFNes - V.35,AFNes - X.21,AFNes - CCITT  V.35,AFNes - RS449/RS422,AFNes - V.35  w/FLASH,AFNes - X.21  w/FLASH,AFNes-CCITT V.35 w/FL,AFNes - RS422 w/FLASH AFNes 16M - V.35,AFNes 16M - X.21,AFNes 16M - CCITT V.35,AFNes 16M - RS449/RS422,AFNes 16M V.35 w/Flash,AFNes 16M X.21 w/Flash,AFNes 16M CCITT V.35 w/Flash,AFNes 16M RS449/RS422 w/Flash',
        4096 =>
            'AFNes - V.35,AFNes - X.21,AFNes - CCITT  V.35,AFNes - RS449/RS422,AFNes - V.35  w/FLASH,AFNes - X.21  w/FLASH,AFNes-CCITT V.35 w/FL,AFNes - RS422 w/FLASH',
        16384 =>
            'AFNes 16M - V.35,AFNes 16M - X.21,AFNes 16M - CCITT V.35,AFNes 16M - RS449/RS422,AFNes 16M V.35 w/Flash,AFNes 16M X.21 w/Flash,AFNes 16M CCITT V.35 w/Flash,AFNes 16M RS449/RS422 w/Flash',
    },
    216 => {
        0 =>
            'AFNts 2x2,AFNts 2x2 - w/FLASH,AFNTS 2X2 16MB,AFNTS 2X2 16MB FLASH',
        4096  => 'AFNts 2x2,AFNts 2x2 - w/FLASH',
        16384 => 'AFNTS 2X2 16MB,AFNTS 2X2 16MB FLASH',
    },
    217 => {
        0 =>
            'AFNts 1x2,AFNts 1x2 - w/FLASH,AFNTS 1X2 16MB,AFNTS 1X2 16MB FLASH',
        4096  => 'AFNts 1x2,AFNts 1x2 - w/FLASH',
        16384 => 'AFNTS 1X2 16MB,AFNTS 1X2 16MB FLASH',
    },
    225  => 'HSSI - SINGLE PORT',
    232  => 'EASF  0 DEFA & 0 CAMS',
    236  => 'ESAF w/DEFA & 2 CAMS,ESAF w/DEFA & 6 CAMS',
    256  => 'QUAD TOKEN',
    512  => 'SPX NET MODULE',
    769  => 'HOT SWAP SPEX NET MOD',
    1024 => {
        4096  => 'AN-ENET 1X2 SPARE 4F/8D,BAYSTACK AN-ES   8MB',
        8192  => 'AN-ENET 1X2 SPARE 4F/8D,BAYSTACK AN-ES   8MB',
        16384 => 'AN-ENET 1X2 SPARE 4F/16D,BAYSTACK AN-ES  16MB',
    },
    1025 => {
        4096  => 'AN-ENET/TOK 1X1X2 SPARE 4F/8D,BAYSTACK AN-ETS   8MB',
        8192  => 'AN-ENET/TOK 1X1X2 SPARE 4F/8D,BAYSTACK AN-ETS   8MB',
        16384 => 'AN-ENET/TOK 1X1X2 SPARE 4F/16D,BAYSTACK AN-ETS  16MB',
    },
    1026 => {
        4096  => 'AN-HUB SPARE 4F/8D,BAYSTACK ANH-12   8MB',
        8192  => 'AN-HUB SPARE 4F/8D,BAYSTACK ANH-12   8MB',
        16384 => 'AN - HUB SPARE 4F/16D,BAYSTACK ANH-12  16MB',
    },
    1027 => {
        4096  => 'AN-ENET 1X2 SPARE 4F/8D,AN ISDN BRI DAUGHTER CARD',
        8192  => 'AN-ENET 1X2 SPARE 4F/8D,AN ISDN BRI DAUGHTER CARD',
        16384 => 'AN-ENET 1X2 SPARE 4F/16D,AN ISDN BRI DAUGHTER CARD',
    },
    1028 => {
        4096  => 'AN-ENET/TOK 1X1X2 SPARE 4F/8D,AN ISDN BRI DAUGHTER CARD',
        8192  => 'AN-ENET/TOK 1X1X2 SPARE 4F/8D,AN ISDN BRI DAUGHTER CARD',
        16384 => 'AN-ENET/TOK 1X1X2 SPARE 4F/16D,AN ISDN BRI DAUGHTER CARD',
    },
    1029 => {
        4096  => 'AN-HUB SPARE 4F/8D,AN ISDN BRI DAUGHTER CARD',
        8192  => 'AN-HUB SPARE 4F/8D,AN ISDN BRI DAUGHTER CARD',
        16384 => 'AN - HUB SPARE 4F/16D,AN ISDN BRI DAUGHTER CARD',
    },
    1030 => {
        4096 =>
            'AN 3RD SYNC DAUGHTER CARD,AN-ENET 1X2 SPARE 4F/8D,BAYSTACK AN-ES   8MB',
        8192 =>
            'AN 3RD SYNC DAUGHTER CARD,AN-ENET 1X2 SPARE 4F/8D,BAYSTACK AN-ES   8MB',
        16384 =>
            'AN 3RD SYNC DAUGHTER CARD,AN-ENET 1X2 SPARE 4F/16D,BAYSTACK AN-ES  16MB',
    },
    1031 => {
        4096 =>
            'AN 3RD SYNC DAUGHTER CARD,AN-ENET/TOK 1X1X2 SPARE 4F/8D,BAYSTACK AN-ETS   8MB',
        8192 =>
            'AN 3RD SYNC DAUGHTER CARD,AN-ENET/TOK 1X1X2 SPARE 4F/8D,BAYSTACK AN-ETS   8MB',
        16384 =>
            'AN 3RD SYNC DAUGHTER CARD,AN-ENET/TOK 1X1X2 SPARE 4F/16D,BAYSTACK AN-ETS  16MB',
    },
    1032 => {
        4096 =>
            'AN 3RD SYNC DAUGHTER CARD,AN-HUB SPARE 4F/8D,BAYSTACK ANH-12   8MB',
        8192 =>
            'AN 3RD SYNC DAUGHTER CARD,AN-HUB SPARE 4F/8D,BAYSTACK ANH-12   8MB',
        16384 =>
            'AN 3RD SYNC DAUGHTER CARD,AN - HUB SPARE 4F/16D,BAYSTACK ANH-12  16MB',
    },
    1033 => {
        4096 =>
            'AN 2ND ENET DAUGHTER CARD,AN-ENET 1X2 SPARE 4F/8D,BAYSTACK AN-ES   8MB',
        8192 =>
            'AN 2ND ENET DAUGHTER CARD,AN-ENET 1X2 SPARE 4F/8D,BAYSTACK AN-ES   8MB',
        16384 =>
            'AN 2ND ENET DAUGHTER CARD,AN-ENET 1X2 SPARE 4F/16D,BAYSTACK AN-ES  16MB',
    },
    1035 => {
        4096 =>
            'AN 2ND ENET DAUGHTER CARD,AN-HUB SPARE 4F/8D,BAYSTACK ANH-12   8MB',
        8192 =>
            'AN 2ND ENET DAUGHTER CARD,AN-HUB SPARE 4F/8D,BAYSTACK ANH-12   8MB',
        16384 =>
            'AN 2ND ENET DAUGHTER CARD,AN - HUB SPARE 4F/16D,BAYSTACK ANH-12  16MB',
    },
    1037 => {
        4096  => 'AN-TOK 1X2 SPARE 4F/8D,BAYSTACK AN-TS   8MB',
        8192  => 'AN-TOK 1X2 SPARE 4F/8D,BAYSTACK AN-TS   8MB',
        16384 => 'AN-TOK 1X2 SPARE 4F/16D,BAYSTACK AN-TS  16MB',
    },
    1038 => {
        4096  => 'AN-TOK 1X2 SPARE 4F/8D,AN ISDN BRI DAUGHTER CARD',
        8192  => 'AN-TOK 1X2 SPARE 4F/8D,AN ISDN BRI DAUGHTER CARD',
        16384 => 'AN-TOK 1X2 SPARE 4F/16D,AN ISDN BRI DAUGHTER CARD',
    },
    1039 => {
        4096 =>
            'AN 3RD SYNC DAUGHTER CARD,AN-TOK 1X2 SPARE 4F/8D,BAYSTACK AN-TS   8MB',
        8192 =>
            'AN 3RD SYNC DAUGHTER CARD,AN-TOK 1X2 SPARE 4F/8D,BAYSTACK AN-TS   8MB',
        16384 =>
            'AN 3RD SYNC DAUGHTER CARD,AN-TOK 1X2 SPARE 4F/16D,BAYSTACK AN-TS  16MB',
    },
    1042 => {
        4096  => 'BAYSTACK AN-ETS   8MB,BAYSTACK AN N11 DCM',
        8192  => 'BAYSTACK AN-ETS   8MB,BAYSTACK AN N11 DCM',
        16384 => 'BAYSTACK AN-ETS  16MB,BAYSTACK AN N11 DCM',
    },
    1043 => {
        4096  => 'BAYSTACK AN-ES   8MB,AN ISDN BRI DAUGHTER CARD',
        8192  => 'BAYSTACK AN-ES   8MB,AN ISDN BRI DAUGHTER CARD',
        16384 => 'BAYSTACK AN-ES  16MB,AN ISDN BRI DAUGHTER CARD',
    },
    1044 => {
        4096  => 'BAYSTACK AN-ETS   8MB,AN ISDN BRI DAUGHTER CARD',
        8192  => 'BAYSTACK AN-ETS   8MB,AN ISDN BRI DAUGHTER CARD',
        16384 => 'BAYSTACK AN-ETS  16MB,AN ISDN BRI DAUGHTER CARD',
    },
    1045 => {
        4096  => 'BAYSTACK ANH-12   8MB,AN ISDN BRI DAUGHTER CARD',
        8192  => 'BAYSTACK ANH-12   8MB,AN ISDN BRI DAUGHTER CARD',
        16384 => 'BAYSTACK ANH-12  16MB,AN ISDN BRI DAUGHTER CARD',
    },
    1046 => {
        4096  => 'BAYSTACK AN-TS   8MB,AN ISDN BRI DAUGHTER CARD',
        8192  => 'BAYSTACK AN-TS   8MB,AN ISDN BRI DAUGHTER CARD',
        16384 => 'BAYSTACK AN-TS  16MB,AN ISDN BRI DAUGHTER CARD',
    },
    1047 => {
        4096  => 'BAYSTACK ANH-8  8MB',
        8192  => 'BAYSTACK ANH-8  8MB',
        16384 => 'BAYSTACK ANH-8  16MB',
    },
    1048 => {
        4096  => 'BAYSTACK ANH-8  8MB,BAYSTACK ANH-8 N11 DCM',
        8192  => 'BAYSTACK ANH-8  8MB,BAYSTACK ANH-8 N11 DCM',
        16384 => 'BAYSTACK ANH-8  16MB,BAYSTACK ANH-8 N11 DCM',
    },
    1049 => {
        4096  => 'BAYSTACK ANH-8  8MB,BAYSTACK ANH-8 3RD SYNC DAUGHTER CARD',
        8192  => 'BAYSTACK ANH-8  8MB,BAYSTACK ANH-8 3RD SYNC DAUGHTER CARD',
        16384 => 'BAYSTACK ANH-8  16MB,BAYSTACK ANH-8 3RD SYNC DAUGHTER CARD',
    },
    1050 => {
        4096  => 'BAYSTACK ANH-8  8MB,BAYSTACK ANH-8 2ND ENET DAUGHTER CARD',
        8192  => 'BAYSTACK ANH-8  8MB,BAYSTACK ANH-8 2ND ENET DAUGHTER CARD',
        16384 => 'BAYSTACK ANH-8  16MB,BAYSTACK ANH-8 2ND ENET DAUGHTER CARD',
    },
    1051 => {
        4096  => 'BAYSTACK ANH-8  8MB,BAYSTACK ANH-8 ISDN BRI DAUGHTER CARD',
        8192  => 'BAYSTACK ANH-8  8MB,BAYSTACK ANH-8 ISDN BRI DAUGHTER CARD',
        16384 => 'BAYSTACK ANH-8  16MB,BAYSTACK ANH-8 ISDN BRI DAUGHTER CARD',
    },
    1052 => {
        4096 =>
            'BAYSTACK ANH-8  8MB,BAYSTACK ANH-8 3RD SYNC DAUGHTER CARD,BAYSTACK ANH-8 N11 DCM',
        8192 =>
            'BAYSTACK ANH-8  8MB,BAYSTACK ANH-8 3RD SYNC DAUGHTER CARD,BAYSTACK ANH-8 N11 DCM',
        16384 =>
            'BAYSTACK ANH-8  16MB,BAYSTACK ANH-8 3RD SYNC DAUGHTER CARD,BAYSTACK ANH-8 N11 DCM',
    },
    1053 => {
        4096 =>
            'BAYSTACK ANH-8  8MB,BAYSTACK ANH-8 2ND ENET DAUGHTER CARD,BAYSTACK ANH-8 N11 DCM',
        8192 =>
            'BAYSTACK ANH-8  8MB,BAYSTACK ANH-8 2ND ENET DAUGHTER CARD,BAYSTACK ANH-8 N11 DCM',
        16384 =>
            'BAYSTACK ANH-8  16MB,BAYSTACK ANH-8 2ND ENET DAUGHTER CARD,BAYSTACK ANH-8 N11 DCM',
    },
    1054 => {
        4096 =>
            'BAYSTACK ANH-8  8MB,BAYSTACK ANH-8 ISDN BRI DAUGHTER CARD,BAYSTACK ANH-8 N11 DCM',
        8192 =>
            'BAYSTACK ANH-8  8MB,BAYSTACK ANH-8 ISDN BRI DAUGHTER CARD,BAYSTACK ANH-8 N11 DCM',
        16384 =>
            'BAYSTACK ANH-8  16MB,BAYSTACK ANH-8 ISDN BRI DAUGHTER CARD,BAYSTACK ANH-8 N11 DCM',
    },
    1055 => {
        4096  => 'BAYSTACK AN-ES   8MB,BAYSTACK AN N11 DCM',
        8192  => 'BAYSTACK AN-ES   8MB,BAYSTACK AN N11 DCM',
        16384 => 'BAYSTACK AN-ES  16MB,BAYSTACK AN N11 DCM',
    },
    1056 => {
        4096 =>
            'BAYSTACK AN-ES   8MB,AN 3RD SYNC DAUGHTER CARD,BAYSTACK AN N11 DCM',
        8192 =>
            'BAYSTACK AN-ES   8MB,AN 3RD SYNC DAUGHTER CARD,BAYSTACK AN N11 DCM',
        16384 =>
            'BAYSTACK AN-ES  16MB,AN 3RD SYNC DAUGHTER CARD,BAYSTACK AN N11 DCM',
    },
    1057 => {
        4096 =>
            'BAYSTACK AN-ES   8MB,AN 2ND ENET DAUGHTER CARD,BAYSTACK AN N11 DCM',
        8192 =>
            'BAYSTACK AN-ES   8MB,AN 2ND ENET DAUGHTER CARD,BAYSTACK AN N11 DCM',
        16384 =>
            'BAYSTACK AN-ES  16MB,AN 2ND ENET DAUGHTER CARD,BAYSTACK AN N11 DCM',
    },
    1059 => {
        4096 =>
            'BAYSTACK AN-ETS   8MB,AN 3RD SYNC DAUGHTER CARD,BAYSTACK AN N11 DCM',
        8192 =>
            'BAYSTACK AN-ETS   8MB,AN 3RD SYNC DAUGHTER CARD,BAYSTACK AN N11 DCM',
        16384 =>
            'BAYSTACK AN-ETS  16MB,AN 3RD SYNC DAUGHTER CARD,BAYSTACK AN N11 DCM',
    },
    1062 => {
        4096 =>
            'BAYSTACK AN-ES   8MB,AN ISDN BRI DAUGHTER CARD,BAYSTACK AN N11 DCM',
        8192 =>
            'BAYSTACK AN-ES   8MB,AN ISDN BRI DAUGHTER CARD,BAYSTACK AN N11 DCM',
        16384 =>
            'BAYSTACK AN-ES  16MB,AN ISDN BRI DAUGHTER CARD,BAYSTACK AN N11 DCM',
    },
    1063 => {
        4096 =>
            'BAYSTACK AN-ETS   8MB,AN ISDN BRI DAUGHTER CARD,BAYSTACK AN N11 DCM',
        8192 =>
            'BAYSTACK AN-ETS   8MB,AN ISDN BRI DAUGHTER CARD,BAYSTACK AN N11 DCM',
        16384 =>
            'BAYSTACK AN-ETS  16MB,AN ISDN BRI DAUGHTER CARD,BAYSTACK AN N11 DCM',
    },
    1280 => 'DUAL ENET NET MODULE',
    1536 => 'DUAL SYNC NET MODULE',
    1537 => 'DUAL SYNC NET MODULE',
    1538 => 'DUAL SYNC NET MODULE',
    1540 => 'DUAL SYNC NET MODULE',
    1541 => 'DUAL SYNC NET MODULE',
    1542 => 'DUAL SYNC NET MODULE',
    1544 => 'DUAL SYNC NET MODULE',
    1545 => 'DUAL SYNC NET MODULE',
    1546 => 'DUAL SYNC NET MODULE',
    1584 => 'DUAL SYNC NET MODULE,ASN ISDN DAUGHTER CARD',
    1585 => 'DUAL SYNC NET MODULE,ASN ISDN DAUGHTER CARD',
    1586 => 'DUAL SYNC NET MODULE,ASN ISDN DAUGHTER CARD',
    1588 => 'DUAL SYNC NET MODULE,ASN ISDN DAUGHTER CARD',
    1589 => 'DUAL SYNC NET MODULE,ASN ISDN DAUGHTER CARD',
    1590 => 'DUAL SYNC NET MODULE,ASN ISDN DAUGHTER CARD',
    1592 => 'DUAL SYNC NET MODULE,ASN ISDN DAUGHTER CARD',
    1593 => 'DUAL SYNC NET MODULE,ASN ISDN DAUGHTER CARD',
    1594 => 'DUAL SYNC NET MODULE,ASN ISDN DAUGHTER CARD',
    1793 => 'MUTLIMODE FDDI NET MODULE',
    1801 => 'SINGLEMODE FDDI NET MODULE',
    1825 => 'S.M. PHY A FDDI NET MODULE',
    1833 => 'S.M. PHY B FDDI NET MODULE',
    2048 => 'DUAL TOKEN NET MODULE',
    2304 => '100 BASE-TX NET MODULE',
    2560 => 'QUAD ISDN BRI NET MOD',
    2816 => 'MCE1 NET MODULE',
    3584 => 'SINGLE HSSI NET MODULE',
    4098 => 'ATM LINK - OC3 MULTIMODE',
    4099 => 'ATM LINK - OC3 SINGLEMODE',
    4352 => 'OCTAL SYNC LINK MODULE',
    4353 =>
        'OCTAL SYNC LINK MODULE,32 CONTEXTS HARDWARE COMPRESSION DGHTR. CARD',
    4354 =>
        'OCTAL SYNC LINK MODULE,128 CONTEXTS HARDWARE COMPRESSION DGHTR. CARD',
    4608 => 'SONET/SDH MMF LINK',
    4609 => 'SONET/SDH SMF LINK',
    4864 => '100 BASE-Tx ETHERNET',
    5376 => 'QUAD PORT MULTICHANNEL T1 (QMCT1) RJ48',
    5377 => 'QUAD PORT MULTICHANNEL T1 (QMCT1) DB15',
    5378 => 'QUAD PORT MULTICHANNEL T1 DS0A (QMCT1 w/DS0A) DB15',
    6144 => '4-PORT 10/100BASE-TX',
    6145 => '4-PORT 100BASE-FX',
    6400 => '1000BASE-SX',
    6401 => '1000BASE-LX',
    8448 => 'SRM-L',
    8704 => 'ARN Motherboard Single Token Ring',
    8720 => 'ARN Motherboard Single Ethernet',
    8728 => 'ARN Motherboard Single 10/100BASE-TX',
    8729 => 'ARN Motherboard Single 10/100BASE-FX',
    8736 => 'ARN Serial Adapter Module',
    8752 => 'ARN V.34 Modem Adapter Module',
    8768 => 'ARN 56/64 DSU/CSU Adapter Module',
    8784 => 'ARN ISDN BRI S/T Adapter Module',
    8800 => 'ARN ISDN BRI U Adapter Module',
    8816 => 'ARN Token Ring Expansion Module',
    8832 => 'ARN Ethernet Expansion Module',
    8848 => 'ARN Tri Serial Expansion Module',
    8864 => 'ARN Ethernet and Tri-Serial Expansion Module',
    8880 => 'ARN Token Ring and Tri-Serial Expansion Module',
    8896 => 'arnmbenx10',
    8912 => 'arnmbtrx10',
    8928 => 'arnpbenx10',
    8944 => 'arnpbtrx10',
    8960 => 'arnpbtenx10',
    8976 => 'arnpbttrx10',
);

%PROCID_MAP = (
    1 => 'SYSTEM CONTROLLER',
    2 => '5MEG ACE25',
    3 => {
        5120 => '5MEG ACE25',
        8192 => '8MEG ACE25',
    },
    4 => {
        4096  => 'ACE32',
        8192  => '8MEG ACE32',
        16384 => '16MEG ACE32',
    },
    5     => 'AFN',
    6     => 'LN',
    7     => 'FLASH SYSTEM CTRL.',
    16384 => 'AN',
    32    => {
        4096  => 'ARN Ethernet - 4 MEG',
        8192  => 'ARN Ethernet - 8 MEG',
        16384 => 'ARN Ethernet - 16 MEG',
        32768 => 'ARN Ethernet - 32 MEG',
    },
    256 => 'FAST ROUTING ENGINE',
    768 => {
        8192  => 'FRE2 - 8MEG',
        16384 => 'FRE2 - 16MEG',
        24576 => 'FRE2 - 24MEG',
        32768 => 'FRE2 - 32MEG',
    },
    769 => {
        8192  => 'FRE2 060 - 8MEG',
        16384 => 'FRE2 060 - 16MEG',
        32768 => 'FRE2 060 - 32MEG',
        65536 => 'FRE2 060 - 64MEG',
    },
    1024 => {
        8192  => 'ASN MOTHER BOARD - 8MB,ASN TRAY / POWER SUPPLY ASSEMBLY',
        16384 => 'ASN MOTHER BOARD - 16MB,ASN TRAY / POWER SUPPLY ASSEMBLY',
        32768 => 'ASN MOTHER BOARD - 32MB,ASN TRAY / POWER SUPPLY ASSEMBLY',
    },
    1025 => {
        8192  => 'ASN2 MOTHER BOARD - 8MB,ASN TRAY / POWER SUPPLY ASSEMBLY',
        16384 => 'ASN2 MOTHER BOARD - 16MB,ASN TRAY / POWER SUPPLY ASSEMBLY',
        32768 => 'ASN2 MOTHER BOARD - 32MB,ASN TRAY / POWER SUPPLY ASSEMBLY',
    },
    1280 => {
        9216  => 'ARE - 8MB DRAM & 1MB VBM',
        19456 => 'ARE - 16MB DRAM & 3MB VBM',
        38912 => 'ARE -32MB DRAM & 6MB VBM',
        71680 => 'ARE -64MB DRAM & 6MB VBM',
    },
    8704 => 'SRM-F',
    1536 => 'ARE5000',
    1792 => 'ASN500',
    6656 => {
        49152  => 'FRE4-PPC - 32MEG',
        81920  => 'FRE4-PPC - 64MEG',
        147456 => 'FRE4-PPC - 128MEG',
    },
);

sub model {
    my $bayrs = shift;
    my $bp_id = $bayrs->bp_id();

    return defined $MODEL_MAP{$bp_id} ? $MODEL_MAP{$bp_id} : $bp_id;
}

sub vendor {
    return 'nortel';
}

sub os {
    return 'bayrs';
}

sub os_ver {
    my $bayrs = shift;
    my $descr = $bayrs->description();
    return unless defined $descr;

    if ( $descr =~ m/^\s*Image:\s+re[lv]\/((\d+\.){1,3}\d+)/ ) {
        return $1;
    }
    return;
}

sub serial {
    my $bayrs     = shift;
    my $serialnum = $bayrs->bp_serial();
    $serialnum = hex(
        join( '',
            '0x', map { sprintf "%02X", $_ } unpack( "C*", $serialnum ) )
    );

    return $serialnum if defined $serialnum;
    return;
}

sub interfaces {
    my $bayrs       = shift;
    my $description = $bayrs->i_description();
    my $vlan_ids    = $bayrs->wf_global_vlan_id();
    my $vlan_idx    = $bayrs->wf_local_vlan_id();

    my %interfaces = ();
    foreach my $iid ( keys %$description ) {
        my $desc = $description->{$iid};
        next unless defined $desc;

        $desc = $1 if $desc =~ /(^[A-Z]\d+)/;

        $interfaces{$iid} = $desc;
    }
    foreach my $iid ( keys %$vlan_ids ) {
        my $vlan = $vlan_ids->{$iid};
        next unless defined $vlan;
        my $vlan_if = $vlan_idx->{$iid};
        next unless defined $vlan_if;

        my $desc = 'Vlan' . $vlan;

        $interfaces{$vlan_if} = $desc;
    }
    return \%interfaces;
}

sub i_name {
    my $bayrs       = shift;
    my $i_index     = $bayrs->i_index();
    my $description = $bayrs->i_description();
    my $v_name      = $bayrs->wf_vlan_name();
    my $vlan_idx    = $bayrs->wf_local_vlan_id();

    my %i_name;
    foreach my $iid ( keys %$description ) {
        my $name = $description->{$iid};
        next unless defined $name;
        $i_name{$iid} = $name;
    }

    # Get VLAN Virtual Router Interfaces
    foreach my $vid ( keys %$v_name ) {
        my $v_name = $v_name->{$vid};
        next unless defined $v_name;
        my $vlan_if = $vlan_idx->{$vid};
        next unless defined $vlan_if;

        $i_name{$vlan_if} = $v_name;
    }
    return \%i_name;
}

sub i_duplex {
    my $bayrs = shift;

    my $wf_cct    = $bayrs->wf_csmacd_cct();
    my $wf_duplex = $bayrs->wf_duplex();

    my %i_duplex;
    foreach my $if ( keys %$wf_cct ) {
        my $idx = $wf_cct->{$if};
        next unless defined $idx;
        my $duplex = $wf_duplex->{$if};
        next unless defined $duplex;

        my $string = 'half';
        $string = 'full' if $duplex =~ /duplex/i;

        $i_duplex{$idx} = $string;
    }
    return \%i_duplex;
}

sub i_duplex_admin {
    my $bayrs = shift;

    my $wf_cct    = $bayrs->wf_csmacd_cct();
    my $wf_duplex = $bayrs->wf_duplex();
    my $wf_auto   = $bayrs->wf_auto();
    my $wf_slot   = $bayrs->wf_csmacd_slot();
    my $wf_conn   = $bayrs->wf_csmacd_conn();

    my %i_duplex_admin;
    foreach my $if ( keys %$wf_cct ) {
        my $idx = $wf_cct->{$if};
        next unless defined $idx;
        my $duplex = $wf_duplex->{$if};
        next unless defined $duplex;
        my $slot     = $wf_slot->{$if};
        my $conn     = $wf_conn->{$if};
        my $auto_idx = "$slot.$conn";
        my $auto     = $wf_auto->{$auto_idx};

        my $string = 'other';
        if ($auto) {
            $string = 'half';
            $string = 'full' if $auto =~ /duplex/i;
            $string = 'auto' if $auto =~ /nway/i;
        }
        elsif ($duplex) {
            $string = 'half';
            $string = 'full' if $duplex =~ /duplex/i;
        }

        $i_duplex_admin{$idx} = $string;
    }
    return \%i_duplex_admin;
}

sub i_vlan {
    my $bayrs = shift;

    my $wf_cct        = $bayrs->wf_csmacd_cct();
    my $wf_mtu        = $bayrs->wf_csmacd_mtu();
    my $wf_line       = $bayrs->wf_csmacd_line();
    my $wf_local_vid  = $bayrs->wf_local_vlan_id();
    my $wf_global_vid = $bayrs->wf_global_vlan_id();
    my $wf_vport      = $bayrs->wf_vlan_port();

    my %i_vlan;

    # Look for VLANs on Ethernet Interfaces
    foreach my $if ( keys %$wf_cct ) {
        my $idx = $wf_cct->{$if};
        next unless defined $idx;

        # Check MTU size, if unable to carry VLAN tag skip.
        my $mtu = $wf_mtu->{$if};
        next if ( ( $mtu =~ /default/i ) or ( $mtu < 1522 ) );
        my $line  = $wf_line->{$if};
        my @vlans = ();
        foreach my $v_idx ( keys %$wf_vport ) {
            my $port = $wf_vport->{$v_idx};
            next unless defined $port;
            next if ( $port != $line );

            my $vlan = $wf_global_vid->{$v_idx};
            push( @vlans, $vlan );
        }
        my $vlans = join( ',', @vlans );
        $i_vlan{$idx} = $vlans;
    }

    # Add VLAN on VLAN Interfaces
    foreach my $idx ( keys %$wf_global_vid ) {
        my $v_if = $wf_local_vid->{$idx};
        next unless defined $v_if;
        my $vlan = $wf_global_vid->{$idx};
        next unless defined $vlan;

        $i_vlan{$v_if} = $vlan;
    }
    return \%i_vlan;
}

sub root_ip {
    my $bayrs = shift;

    my $ip_index = $bayrs->ip_index();
    my $ip_table = $bayrs->ip_table();

    # Check for CLIP
    foreach my $entry ( keys %$ip_index ) {
        my $idx = $ip_index->{$entry};
        next unless $idx == 0;
        my $clip = $ip_table->{$entry};
        next
            unless ( ( defined $clip )
            and ( $clip ne '0.0.0.0' )
            and ( $bayrs->snmp_connect_ip($clip) ) );
        print " SNMP::Layer3::BayRS::root_ip() using $clip\n"
            if $bayrs->debug();
        return $clip;
    }

    # Check for OSPF Router ID
    my $ospf_ip = $bayrs->ospf_rtr_id();
    if (    ( defined $ospf_ip )
        and ( $ospf_ip ne '0.0.0.0' )
        and ( $bayrs->snmp_connect_ip($ospf_ip) ) )
    {
        print " SNMP::Layer3::BayRS::root_ip() using $ospf_ip\n"
            if $bayrs->debug();
        return $ospf_ip;
    }

    return;
}

# Pseudo ENTITY-MIB methods

sub e_index {
    my $bayrs = shift;

    my $bp_id = $bayrs->bp_id();

    # Don't like polling all these columns to build the index, can't think of
    # a better way right now.  Luckly all this data will be cached for the
    # rest of the e_* methods

    # Using mib leafs so we don't have to define everything in FUNCS

    # Processor - All models should support these
    my $wf_mb = $bayrs->wfHwMotherBdIdOpt()   || {};
    my $wf_db = $bayrs->wfHwDaughterBdIdOpt() || {};
    my $wf_bb = $bayrs->wfHwBabyBdIdOpt()     || {};

    my ( $wf_mod, $wf_mod1, $wf_mod2, $wf_mm, $wf_dm ) = {};

    # Only query objects we need
    # Link Module
    if ( $bp_id !~ /arn|asn/ ) {
        $wf_mod  = $bayrs->wfHwModIdOpt()            || {};
        $wf_mod1 = $bayrs->wfHwModDaughterBd1IdOpt() || {};
        $wf_mod2 = $bayrs->wfHwModDaughterBd2IdOpt() || {};
    }

    # Hardware Module
    if ( $bp_id =~ /arn|asn/ ) {
        $wf_mm = $bayrs->wfHwModuleModIdOpt()        || {};
        $wf_dm = $bayrs->wfHwModuleDaughterBdIdOpt() || {};
    }

    my @slots = ( $wf_mb, $wf_db, $wf_bb, $wf_mod, $wf_mod1, $wf_mod2 );
    my @mods = ( $wf_mm, $wf_dm );

    # We're going to hack an index: Slot/Module/Postion
    my %wf_e_index;

    # Chassis on BN types
    if ( $bp_id !~ /an|arn|asn/ ) {
        $wf_e_index{1} = 1;
    }

    # Handle Processor / Link Modules first
    foreach my $idx ( keys %$wf_mb ) {
        my $index = "$idx" . "0000";
        unless ( $bp_id =~ /an|arn|asn/ ) {
            $wf_e_index{$index} = $index;
        }
        foreach my $slot (@slots) {
            $index++;
            $wf_e_index{$index} = $index if $slot->{$idx};
        }
    }

    # Handle Hardware Modules
    foreach my $iid ( keys %$wf_mm ) {
        my $main_mod = $wf_mm->{$iid};
        next unless $main_mod;
        my $index = join( '', map { sprintf "%02d", $_ } split /\./, $iid );
        $index = "$index" . "00";
        $wf_e_index{$index} = $index;
        foreach my $mod (@mods) {
            $index++;
            $wf_e_index{$index} = $index if $mod->{$iid};
        }
    }
    return \%wf_e_index;
}

sub e_class {
    my $bayrs = shift;

    my $bp_id = $bayrs->bp_id();

    my $wf_e_idx = $bayrs->e_index() || {};

    my %wf_e_class;
    foreach my $iid ( keys %$wf_e_idx ) {
        if ( $iid == 1 ) {
            $wf_e_class{$iid} = 'chassis';
        }
        elsif ( $bp_id =~ /an|arn|asn/ and $iid == '10001' ) {
            $wf_e_class{$iid} = 'chassis';
        }
        elsif ( $iid =~ /(00){1,2}$/ ) {
            $wf_e_class{$iid} = 'container';
        }
        else {
            $wf_e_class{$iid} = 'module';
        }
    }
    return \%wf_e_class;
}

sub e_name {
    my $bayrs = shift;

    my $bp_id = $bayrs->bp_id();
    my $wf_e_idx = $bayrs->e_index() || {};

    my %wf_e_name;

    # Chassis
    foreach my $iid ( keys %$wf_e_idx ) {
        if ( $iid == 1 ) {
            $wf_e_name{$iid} = 'Router';
            next;
        }

        my $pos = substr( $iid, -1 );
        my $sub = substr( $iid, -4, 2 );
        $sub =~ s/^0//;
        my $slot = substr( $iid, -6, 2 );
        $slot =~ s/^0//;

        if ( $bp_id =~ /an|arn|asn/ and $iid == '10001' ) {
            $wf_e_name{$iid} = 'Router';
        }
        elsif ( $iid =~ /(00){2}$/ ) {
            $wf_e_name{$iid} = "Slot $slot";
        }
        elsif ( $iid =~ /(00){1}$/ and $bp_id =~ /asn/ ) {
            $wf_e_name{$iid} = "Module Container $slot $sub";
        }
        elsif ( $iid =~ /(00){1}$/ and $bp_id =~ /an|arn/ ) {
            $sub--;
            if ( $sub == 0 ) {
                $wf_e_name{$iid} = "Motherboard  Container";
            }
            else {
                $wf_e_name{$iid} = "Module Container $sub";
            }
        }
        elsif ( $bp_id !~ /an|arn|asn/ and $iid =~ /1$/ ) {
            $wf_e_name{$iid} = "Processor Slot $slot";
        }
        elsif ( $bp_id =~ /asn/ and $iid =~ /1$/ ) {
            $wf_e_name{$iid} = "Module $slot $sub";
        }
        elsif ( $bp_id =~ /an|arn/ and $iid =~ /1$/ ) {
            $sub--;
            if ( $sub == 0 ) {
                $wf_e_name{$iid} = "Motherboard";
            }
            else {
                $wf_e_name{$iid} = "Module $sub";
            }
        }
        elsif ( $bp_id !~ /asn/ and $iid =~ /2$/ ) {
            $wf_e_name{$iid} = "Processor Daughter Board Slot $slot";
        }
        elsif ( $bp_id !~ /an|arn/ and $iid =~ /2$/ ) {
            $wf_e_name{$iid} = "Processor Daughter Board";
        }
        elsif ( $bp_id =~ /asn/ and $iid =~ /2$/ ) {
            $wf_e_name{$iid} = "Module Daughter Board $slot $sub";
        }
        elsif ( $bp_id =~ /an|arn/ and $iid =~ /2$/ ) {
            $sub--;
            $wf_e_name{$iid} = "Module Daughter Board $sub";
        }
        elsif ( $iid =~ /3$/ ) {
            $wf_e_name{$iid} = "Processor Baby Board Slot $slot";
        }
        elsif ( $iid =~ /4$/ ) {
            $wf_e_name{$iid} = "Link Module Slot $slot";
        }
        elsif ( $iid =~ /5$/ ) {
            $wf_e_name{$iid} = "Link Module Daughter Board 1 Slot $slot";
        }
        elsif ( $iid =~ /6$/ ) {
            $wf_e_name{$iid} = "Link Module Daughter Board 2 Slot $slot";
        }
        else {
            next;
        }
    }
    return \%wf_e_name;
}

sub e_descr {
    my $bayrs = shift;

    my $bp_id = $bayrs->bp_id();

    # Using mib leafs so we don't have to define everything in FUNCS
    # We only have descriptions for the processors and modules
    # Processor
    my $wf_mb     = $bayrs->wfHwMotherBdIdOpt()      || {};
    my $wf_mb_mem = $bayrs->wfHwMotherBdMemorySize() || {};

    my ( $wf_mod, $wf_mm ) = {};

    # Link Module
    if ( $bp_id !~ /arn|asn/ ) {
        $wf_mod = $bayrs->wfHwModIdOpt() || {};
    }

    # Hardware Module
    if ( $bp_id =~ /arn|asn/ ) {
        $wf_mm = $bayrs->wfHwModuleModIdOpt() || {};
    }

    my %wf_e_descr;

    # Chassis
    if ( $bp_id !~ /an|arn|asn/ ) {
        $wf_e_descr{1} = $bayrs->model();
    }

    # Handle Processor / Link Modules first
    foreach my $idx ( keys %$wf_mb ) {
        unless ( $bp_id =~ /an|arn|asn/ ) {
            $wf_e_descr{ "$idx" . "0000" } = 'Slot ' . $idx;
        }
        my $mb_id;
        $mb_id = &SNMP::mapEnum( 'wfHwMotherBdIdOpt', $wf_mb->{$idx} )
            if $wf_mb->{$idx};
        my $mb_mem = $wf_mb_mem->{$idx};
        my $mod_id;
        $mod_id = &SNMP::mapEnum( 'wfHwModIdOpt', $wf_mod->{$idx} )
            if $wf_mod->{$idx};

        # Processor
        if ($mb_id) {
            if ( ref( $PROCID_MAP{$mb_id} ) =~ /HASH/ ) {
                $wf_e_descr{ "$idx" . "0001" }
                    = defined $PROCID_MAP{$mb_id}{$mb_mem}
                    ? $PROCID_MAP{$mb_id}{$mb_mem}
                    : $mb_id;
            }
            else {
                $wf_e_descr{ "$idx" . "0001" }
                    = defined $PROCID_MAP{$mb_id}
                    ? $PROCID_MAP{$mb_id}
                    : $mb_id;
            }
        }

        # Link Module
        if ($mod_id) {
            if ( ref( $MODID_MAP{$mod_id} ) =~ /HASH/ ) {
                $wf_e_descr{ "$idx" . "0004" }
                    = defined $MODID_MAP{$mod_id}{$mb_mem}
                    ? $MODID_MAP{$mod_id}{$mb_mem}
                    : $mod_id;
            }
            else {
                $wf_e_descr{ "$idx" . "0004" }
                    = defined $MODID_MAP{$mod_id}
                    ? $MODID_MAP{$mod_id}
                    : $mod_id;
            }
        }
    }

    # Handle Hardware Modules
    foreach my $iid ( keys %$wf_mm ) {
        next unless ( $wf_mm->{$iid} );
        my $idx = join( '', map { sprintf "%02d", $_ } split /\./, $iid );
        my ( $slot, $mod ) = split /\./, $iid;
        if ( $bp_id =~ /an|arn/ ) {
            $mod--;
            if ( $mod == 0 ) {
                $wf_e_descr{ "$idx" . "00" } = "Motherboard Container";
            }
            else {
                $wf_e_descr{ "$idx" . "00" } = "Module Container $mod";
            }
        }
        else {
            $wf_e_descr{ "$idx" . "00" } = "Module Container $slot $mod";
        }
        my $mm_id = &SNMP::mapEnum( 'wfHwModuleModIdOpt', $wf_mm->{$iid} );
        my $index = join( '', map { sprintf "%02d", $_ } split /\./, $iid );
        $wf_e_descr{ "$index" . "01" }
            = defined $MODID_MAP{$mm_id} ? $MODID_MAP{$mm_id} : $mm_id;
    }
    return \%wf_e_descr;
}

sub e_type {
    my $bayrs = shift;

    my $bp_id = $bayrs->bp_id();

    # Using mib leafs so we don't have to define everything in FUNCS
    # Processor
    my $wf_mb = $bayrs->wfHwMotherBdIdOpt()   || {};
    my $wf_db = $bayrs->wfHwDaughterBdIdOpt() || {};
    my $wf_bb = $bayrs->wfHwBabyBdIdOpt()     || {};

    my ( $wf_mod, $wf_mod1, $wf_mod2, $wf_mm, $wf_dm ) = {};

    # Link Module
    if ( $bp_id !~ /arn|asn/ ) {
        $wf_mod  = $bayrs->wfHwModIdOpt()            || {};
        $wf_mod1 = $bayrs->wfHwModDaughterBd1IdOpt() || {};
        $wf_mod2 = $bayrs->wfHwModDaughterBd2IdOpt() || {};
    }

    # Hardware Module
    if ( $bp_id =~ /arn|asn/ ) {
        $wf_mm = $bayrs->wfHwModuleModIdOpt()        || {};
        $wf_dm = $bayrs->wfHwModuleDaughterBdIdOpt() || {};
    }

    my @slots = ( $wf_mb, $wf_db, $wf_bb, $wf_mod, $wf_mod1, $wf_mod2 );
    my @mods = ( $wf_mm, $wf_dm );

    my %wf_e_type;

    # Chassis
    if ( $bp_id !~ /an|arn|asn/ ) {
        $wf_e_type{1} = $bayrs->bp_id();
    }

    # Handle Processor / Link Modules first
    foreach my $idx ( keys %$wf_mb ) {
        my $index = "$idx" . "0000";
        unless ( $bp_id =~ /an|arn|asn/ ) {
            $wf_e_type{$index} = "zeroDotZero";
        }
        foreach my $slot (@slots) {
            $index++;
            $wf_e_type{$index} = $slot->{$idx} if $slot->{$idx};
        }
    }

    # Handle Hardware Modules
    foreach my $iid ( keys %$wf_mm ) {
        my $main_mod = $wf_mm->{$iid};
        next unless $main_mod;
        my $index = join( '', map { sprintf "%02d", $_ } split /\./, $iid );
        $index = "$index" . "00";
        $wf_e_type{$index} = "zeroDotZero";
        foreach my $mod (@mods) {
            $index++;
            $wf_e_type{$index} = $mod->{$iid} if $mod->{$iid};
        }
    }
    return \%wf_e_type;
}

sub e_hwver {
    my $bayrs = shift;

    my $bp_id = $bayrs->bp_id();

    # Using mib leafs so we don't have to define everything in FUNCS
    # Processor
    my $wf_mb = $bayrs->wfHwMotherBdRev()   || {};
    my $wf_db = $bayrs->wfHwDaughterBdRev() || {};
    my $wf_bb = $bayrs->wfHwBabyBdRev()     || {};

    my ( $wf_mod, $wf_mod1, $wf_mod2, $wf_mm ) = {};

    # Link Module
    if ( $bp_id !~ /arn|asn/ ) {
        $wf_mod  = $bayrs->wfHwModRev()            || {};
        $wf_mod1 = $bayrs->wfHwModDaughterBd1Rev() || {};
        $wf_mod2 = $bayrs->wfHwModDaughterBd2Rev() || {};
    }

    # Hardware Module
    if ( $bp_id =~ /arn|asn/ ) {
        $wf_mm = $bayrs->wfHwModuleModRev() || {};
    }

    my @slots = ( $wf_mb, $wf_db, $wf_bb, $wf_mod, $wf_mod1, $wf_mod2 );

    my %wf_e_hwver;

    # Chassis
    if ( $bp_id !~ /an|arn|asn/ ) {
        my $bp_rev = $bayrs->wfHwBpRev();
        $bp_rev = hex(
            join( '',
                '0x', map { sprintf "%02X", $_ } unpack( "C*", $bp_rev ) )
        );

        $wf_e_hwver{1} = $bp_rev;
    }

    # Handle Processor / Link Modules first
    foreach my $idx ( keys %$wf_mb ) {
        my $index = "$idx" . "0000";
        foreach my $slot (@slots) {
            $index++;
            next unless ( $slot->{$idx} );
            my $mod;
            $mod = hex(
                join( '',
                    '0x',
                    map { sprintf "%02X", $_ } unpack( "C*", $slot->{$idx} ) )
            ) if $slot->{$idx};
            $wf_e_hwver{$index} = $mod if $mod;
        }
    }
    foreach my $iid ( keys %$wf_mm ) {
        my $index = join( '', map { sprintf "%02d", $_ } split /\./, $iid );
        my $mod;
        $mod = hex(
            join( '',
                '0x',
                map { sprintf "%02X", $_ } unpack( "C*", $wf_mm->{$iid} ) )
        ) if $wf_mm->{$iid};
        $index = "$index" . "00";
        $index++;
        next unless ( $wf_mm->{$iid} );
        $wf_e_hwver{$index} = $mod if $mod;
    }
    return \%wf_e_hwver;
}

sub e_vendor {
    my $bayrs = shift;

    my $wf_e_idx = $bayrs->e_index() || {};

    my %wf_e_vendor;
    foreach my $iid ( keys %$wf_e_idx ) {
        $wf_e_vendor{$iid} = 'nortel';
    }
    return \%wf_e_vendor;
}

sub e_serial {
    my $bayrs = shift;

    my $bp_id = $bayrs->bp_id();

    # Processor
    my $wf_mb = $bayrs->wf_hw_mobo_ser() || {};
    my $wf_db = $bayrs->wf_hw_db_ser()   || {};
    my $wf_bb = $bayrs->wf_hw_bb_ser()   || {};

    my ( $wf_mod, $wf_mod1, $wf_mod2, $wf_mm ) = {};

    # Link Module
    if ( $bp_id !~ /arn|asn/ ) {
        $wf_mod  = $bayrs->wf_hw_mod_ser() || {};
        $wf_mod1 = $bayrs->wf_hw_md1_ser() || {};
        $wf_mod2 = $bayrs->wf_hw_md2_ser() || {};
    }

    # Hardware Module
    if ( $bp_id =~ /arn|asn/ ) {
        $wf_mm = $bayrs->wf_hw_mm_ser() || {};
    }

    my @slots = ( $wf_mb, $wf_db, $wf_bb, $wf_mod, $wf_mod1, $wf_mod2 );

    my %wf_e_serial;

    # Chassis
    if ( $bp_id !~ /an|arn|asn/ ) {
        $wf_e_serial{1} = $bayrs->serial();
    }

    # Handle Processor / Link Modules first
    foreach my $idx ( keys %$wf_mb ) {
        my $index = "$idx" . "0000";
        foreach my $slot (@slots) {
            $index++;
            my $mod = $slot->{$idx};
            next unless ($mod);
            $wf_e_serial{$index} = $mod if $mod;
        }
    }

    # Handle Hardware Modules
    foreach my $iid ( keys %$wf_mm ) {
        my $index = join( '', map { sprintf "%02d", $_ } split /\./, $iid );
        my $mod = $wf_mm->{$iid};
        $index = "$index" . "00";
        $index++;
        next unless ($mod);
        $wf_e_serial{$index} = $mod if $mod;
    }
    return \%wf_e_serial;
}

sub e_pos {
    my $bayrs = shift;

    my $wf_e_idx = $bayrs->e_index() || {};
    my $bp_id = $bayrs->bp_id();

    my %wf_e_pos;
    foreach my $iid ( keys %$wf_e_idx ) {
        if ( $iid == 1 ) {
            $wf_e_pos{$iid} = -1;
            next;
        }

        my $pos  = substr( $iid, -1 );
        my $sub  = substr( $iid, -4, 2 );
        my $slot = substr( $iid, -6, 2 );

        if ( $bp_id =~ /an|arn|asn/ and $iid == '10001' ) {
            $wf_e_pos{$iid} = -1;
        }
        elsif ( $iid =~ /(00){2}$/ ) {
            $wf_e_pos{$iid} = $slot;
        }
        elsif ( $iid =~ /(00){1}$/ ) {
            $wf_e_pos{$iid} = $sub;
        }
        else {
            $wf_e_pos{$iid} = $pos;
        }
    }
    return \%wf_e_pos;
}

sub e_fwver {
    my $bayrs = shift;

    # Only on Processor
    my $wf_mb = $bayrs->wf_hw_boot() || {};
    my %wf_e_hwver;
    foreach my $idx ( keys %$wf_mb ) {
        my $fw = $wf_mb->{$idx};
        next unless $fw;

        $wf_e_hwver{ "$idx" . "0001" } = $fw;
    }
    return \%wf_e_hwver;
}

sub e_swver {
    my $bayrs = shift;

    # Only on Processor
    my $wf_mb = $bayrs->wfHwActiveImageSource() || {};
    my %wf_e_swver;
    foreach my $idx ( keys %$wf_mb ) {
        my $sw = $wf_mb->{$idx};
        next unless $sw;

        $wf_e_swver{ "$idx" . "0001" } = $sw;
    }
    return \%wf_e_swver;
}

sub e_parent {
    my $bayrs = shift;

    my $wf_e_idx = $bayrs->e_index() || {};
    my $bp_id = $bayrs->bp_id();

    my %wf_e_parent;
    foreach my $iid ( keys %$wf_e_idx ) {
        if ( $iid == 1 ) {
            $wf_e_parent{$iid} = 0;
            next;
        }

        my $mod  = substr( $iid, -4, 2 );
        my $slot = substr( $iid, -6, 2 );

        if ( $bp_id =~ /an|arn|asn/ and $iid == '10001' ) {
            $wf_e_parent{$iid} = 0;
        }
        elsif ( $iid =~ /(00){1,2}$/ ) {
            my $parent = 1;
            $parent = '10001' if ( $bp_id =~ /an|arn|asn/ );
            $wf_e_parent{$iid} = $parent;
        }
        elsif ( $mod != 0 ) {
            $wf_e_parent{$iid} = "$slot" . "$mod" . "00";
        }
        else {
            $wf_e_parent{$iid} = "$slot" . "0000";
        }
    }
    return \%wf_e_parent;
}

sub munge_hw_rev {
    my $hw_boot = shift;

    my @bytes = map { sprintf "%02X", $_ } unpack( "C*", $hw_boot );
    my $major = hex( "$bytes[0]" . "$bytes[1]" );
    my $minor = hex( "$bytes[2]" . "$bytes[3]" );

    my $rev = "$major.$minor";
    return $rev if defined($rev);
    return;
}

sub munge_wf_serial {
    my $wf_serial = shift;

    my $serial = hex(
        join( '',
            '0x', map { sprintf "%02X", $_ } unpack( "C*", $wf_serial ) )
    );

    return $serial if defined($serial);
    return;
}

1;
__END__

=head1 NAME

SNMP::Info::Layer3::BayRS - SNMP Interface to Nortel routers running BayRS.

=head1 AUTHOR

Eric Miller

=head1 SYNOPSIS

 # Let SNMP::Info determine the correct subclass for you. 
 my $bayrs = new SNMP::Info(
                          AutoSpecify => 1,
                          Debug       => 1,
                          DestHost    => 'myswitch',
                          Community   => 'public',
                          Version     => 2
                        ) 
    or die "Can't connect to DestHost.\n";

 my $class      = $bayrs->class();
 print "SNMP::Info determined this device to fall under subclass : $class\n";

=head1 DESCRIPTION

Abstraction subclass for routers running Nortel BayRS.  

For speed or debugging purposes you can call the subclass directly, but not
after determining a more specific class using the method above. 

 my $bayrs = new SNMP::Info::Layer3::BayRS(...);

=head2 Inherited Classes

=over

=item SNMP::Info

=item SNMP::Info::Bridge

=item SNMP::Info::Layer3

=back

=head2 Required MIBs

=over

=item F<Wellfleet-HARDWARE-MIB>

=item F<Wellfleet-MODULE-MIB>

=item F<Wellfleet-OSPF-MIB>

=item F<Wellfleet-DOT1QTAG-CONFIG-MIB>

=item F<Wellfleet-CSMACD-MIB>

=back

=head2 Inherited MIBs

See L<SNMP::Info/"Required MIBs"> for its own MIB requirements.

See L<SNMP::Info::Bridge/"Required MIBs"> for its own MIB requirements.

See L<SNMP::Info::Layer3/"Required MIBs"> for its own MIB requirements.

=head1 GLOBALS

These are methods that return scalar value from SNMP

=over

=item $bayrs->model()

Returns the model of the BayRS router.  Will translate between the MIB model
and the common model with this map :

    C<%MODEL_MAP = ( 
        'acefn'     => 'FN',
        'aceln'     => 'LN',
        'acecn'     => 'CN',
        'afn'       => 'AFN',
        'in'        => 'IN',
        'an'        => 'AN',
        'arn'       => 'ARN',
        'sys5000'   => '5000',
        'freln'     => 'BLN',
        'frecn'     => 'BCN',
        'frerbln'   => 'BLN-2',
        'asn'       => 'ASN',
        'asnzcable' => 'ASN-Z',
        'asnbcable' => 'ASN-B',
        );>

=item $bayrs->vendor()

Returns 'nortel'

=item $bayrs->os()

Returns 'bayrs'

=item $bayrs->os_ver()

Returns the software version extracted from C<sysDescr>

=item $bayrs->serial()

Returns (C<wfHwBpSerialNumber>) after conversion to ASCII decimal

=item $bayrs->root_ip()

Returns the primary IP used to communicate with the router.

Returns the first found:  CLIP (CircuitLess IP), (C<wfOspfRouterId>), or
undefined.

=back

=head2 Globals imported from SNMP::Info

See documentation in L<SNMP::Info/"GLOBALS"> for details.

=head2 Globals imported from SNMP::Info::Bridge

See documentation in L<SNMP::Info::Bridge/"GLOBALS"> for details.

=head2 Globals imported from SNMP::Info::Layer3

See documentation in L<SNMP::Info::Layer3/"GLOBALS"> for details.

=head1 TABLE METHODS

These are methods that return tables of information in the form of a reference
to a hash.

Note:  These methods do not support partial table fetches, a partial can be
passed but the entire table will be returned.

=head2 Overrides

=over

=item $bayrs->interfaces()

Returns reference to the map between IID and physical Port.

The physical port name is stripped to letter and numbers to signify
port type and slot port (S11) if the default platform naming was 
maintained.  Otherwise the port is the interface description. 

=item $bayrs->i_name()

Returns (C<ifDescr>) along with VLAN name (C<wfDot1qTagCfgVlanName>) for VLAN
interfaces.

=item $bayrs->i_duplex()

Returns reference to hash.  Maps port operational duplexes to IIDs for
Ethernet interfaces. 

=item $bayrs->i_duplex_admin()

Returns reference to hash.  Maps port admin duplexes to IIDs for Ethernet
interfaces.

=item $bayrs->i_vlan()

Returns reference to hash.  Maps port VLAN ID to IIDs.

=back

=head2 Pseudo F<ENTITY-MIB> information

These methods emulate F<ENTITY-MIB> Physical Table methods using
F<Wellfleet-HARDWARE-MIB> and F<Wellfleet-MODULE-MIB>.

=over

=item $bayrs->e_index()

Returns reference to hash.  Key and Value: Integer. The index is created by
combining the slot, module, and position into a five or six digit integer.
Slot can be either one or two digits while the module and position are each
two digits padded with leading zero if required.

=item $bayrs->e_class()

Returns reference to hash.  Key: IID, Value: General hardware type.  This
class only returns container and module types.

=item $bayrs->e_descr()

Returns reference to hash.  Key: IID, Value: Human friendly name.

=item $bayrs->e_name()

Returns reference to hash.  Key: IID, Value: Human friendly name.

=item $bayrs->e_hwver()

Returns reference to hash.  Key: IID, Value: Hardware version.

=item $bayrs->e_vendor()

Returns reference to hash.  Key: IID, Value: nortel.

=item $bayrs->e_serial()

Returns reference to hash.  Key: IID, Value: Serial number.

=item $bayrs->e_pos()

Returns reference to hash.  Key: IID, Value: The relative position among all
entities sharing the same parent.

=item $bayrs->e_type()

Returns reference to hash.  Key: IID, Value: Type of component/sub-component
as defined in F<Wellfleet-HARDWARE-MIB> for processors and link modules or
F<Wellfleet-MODULE-MIB> for hardware modules.

=item $bayrs->e_fwver()

Returns reference to hash.  Key: IID, Value: Firmware revision.  Only
available on processors.

=item $bayrs->e_swver()

Returns reference to hash.  Key: IID, Value: Software revision.  Only
available on processors.

=item $bayrs->e_parent()

Returns reference to hash.  Key: IID, Value: The value of e_index() for the
entity which 'contains' this entity.  A value of zero indicates	this entity
is not contained in any other entity.

=back

=head2 Table Methods imported from SNMP::Info

See documentation in L<SNMP::Info/"TABLE METHODS"> for details.

=head2 Table Methods imported from SNMP::Info::Bridge

See documentation in L<SNMP::Info::Bridge/"TABLE METHODS"> for details.

=head2 Table Methods imported from SNMP::Info::Layer3

See documentation in L<SNMP::Info::Layer3/"TABLE METHODS"> for details.

=head1 Data Munging Callback Subroutines

=over

=item $extreme->munge_hw_rev()

Converts octets to a decimal major.minor string.

=item $extreme->munge_wf_serial()

Coverts octets to a decimal string.

=back

=cut
