#!/bin/bash

# F.O.B. (Flexible Orange Box)
# Type II MDMF (Multiple Data Message Format) Caller ID Generator
# (C) InterLinked / PhreakNet - https://phreaknet.org / v1.0 (021-04-26)
# apache-2.0. This program is provided with absolutely no warranty or guarantees. The author is not liable for any misuse of or effects resulting from usage of this program.

# DESCRIPTION: This is a powerful, flexible, and complete Type II Caller ID generator (or orange box). It supports ALL standardized MDMF presentation parameters, even those which most CLID generators do not support.
# PRE-REQS: In addition to the standard GNU utilities, this program requires bc, minimodem, and sox.
# This program has been optimized for use with Asterisk. You will need to provide the Subscriber Alerting Signal, CPE Alerting Signal, then wait for an ACK, then play the audio returned by this script, then a quick dummy audio file to suppress Asterisk-generated echo.

## Specification Sources, which were helpful in compiling this program:
## http://www.bulipi-eee.tuiasi.ro/archive/2015/fasc.1/p7_f1_2015.pdf pg. 7
## https://web.archive.org/web/20080908040823/http://www.bell.cdn-telco.com/bid/BID-0001Multiple.pdf pg. 15
##	- located at https://web.archive.org/web/20160404063251/http://www.bell.cdn-telco.com/bid/
##	- thanks to: https://sourceforge.net/p/ncid/discussion/275237/thread/23484d6d/
## https://web.archive.org/web/20080908040823/http://www.bell.cdn-telco.com/bid/BID-0001Multiple.pdf

# Primary arguments: please provide
timezone=$1 # Time Zone (if not specified, it should default to the system time zone)
number=$2 # ANI / CALLERID(num)
name="$3" # name / CALLERID(name)
pres=$4 # O = Out of Area / Number Unavailable, P = Private (Withheld), empty otherwise, derived from CALLERID(pres)
# Secondary arguments: are not sent unless a non-empty argument is provided
dnis=$5 # called number (DNIS or RDNIS), or empty to not send
reason=$6 # redirection reason, if call was forwarded, or empty to not send
ldc=$7 # 1 for long distance or empty to not send
messages=$8 # number of messages (0 or greater), or empty to not send

# Initialize (hopefully) unique file names
rand=`shuf -i 1-9999999 -n 1`
prefix=/tmp/calleridfsk_$rand
pre="${prefix}.pre"
text="${prefix}.txt"
binary="${prefix}.bin"
audio0="${prefix}_0.wav"
audio1="${prefix}_1.wav"
audio="${prefix}.wav"
ulaw="${prefix}_final.ulaw"

# Initialize files, clearing them in case they already exist
echo -n "" > $text # -n, because we don't want to add a 0x0A (carriage return) to the file
echo -n "" > $pre
echo -n "" > $binary

# Cleanup arguments into the format we need
if [ "$ldc" == "1" ]; then
	ldc=1
else
	ldc=
fi
if [ "${pres:0:6}" == "prohib" ]; then
	pres="P"
elif [ "${pres:0:7}" == "unavail" ]; then
	pres="O"
else
	pres=""
fi

# PRESENTATION LAYER: each is: Parameter Type, Length (1 byte), Bytes (0+)
message="" # initialize string

function preslayer { # $1 = Parameter Type in hex, $2 = Parameter Value in ASCII, $3 = 1 if $2 is already hex instead of ASCII, empty otherwise
	echo -e -n $1 >> $binary # Parameter Type is already hex
	if [ ${#2} -gt 0 ]; then
		if [ "$3" == "1" ]; then # $2 is actually hex, not ASCII
			printf '%02X' 1 | xxd -r -p >> $binary # Parameter Length (1 byte) - because the data is hex, the length is only 1 byte
			echo -e -n "$2" >> $binary
		else
			printf '%02X' ${#2} | xxd -r -p >> $binary # Parameter Length (1 byte), convert hex string to literal hex
			printf '%s' "$2" | xxd -p | xxd -r -p >> $binary # include message if it's greater than 0 bytes, convert the ASCII to hex
		fi
	else
		printf '%02X' 0 | xxd -r -p >> $binary # Parameter Length (1 byte) - no data at all, so this should be 0, and we don't send any data at all
	fi
}

# 0x11 = Call Type
if [ ${#1} -gt 0 ]; then
	datestring=`TZ=":$1" date +%m%d%H%M`
else
	datestring=`date +%m%d%H%M`
fi
preslayer '\x01' $datestring # Time & Date
if [ "$pres" == "" ]; then # Calling Line DN
	preslayer '\x02' "$number"
fi
if [ "$dnis" != "" ]; then # Redirecting number
	preslayer '\x03' "$dnis"
fi
if [ "$pres" != "" ]; then # Reason for DN asbence
	preslayer '\x04' "$pres"
fi
if [ "$reason" == "cfb" ]; then # Reason for redirection (values are in base-16/hex) - page 55: https://www.ti.com/lit/ug/spru632/spru632.pdf
	preslayer '\x05' '\x01' 1 # Call forwarded on busy
elif [ "$reason" == "cfnr" ]; then
	preslayer '\x05' '\x02' 1 # Call forwarded on no reply
elif [ "$reason" == "cfu" ]; then
	preslayer '\x05' '\x03' 1 # Unconditional forwarded call
elif [ "$reason" == "cf_dte" ]; then
	preslayer '\x05' '\x04' 1 # Deflected call (after alerting)
elif [ "$reason" == "deflection" ]; then
	preslayer '\x05' '\x05' 1 # Deflected call (immediate)
elif [ "$reason" == "cfu" ]; then
	preslayer '\x05' '\x06' 1 # Call forwarded on inability to reach mobile subscriber
elif [ "$reason" != "" ]; then # some other reason from https://wiki.asterisk.org/wiki/display/AST/Function_REDIRECTING
	if [ "$reason" != "unknown" ]; then
		preslayer '\x05' '\x03' 1 # assume unconditionally forwarded
	fi
fi # else not redirected / Values in the range E016-FF16 are reserved for network operators.
if [ "$ldc" == "L" ]; then # Call Qualifier
	preslayer '\x06' "L" # only valid option is L (0x4C) = Long Distance Indicator
fi
if [ "$pres" == "" ]; then # Caller Name/Text
	preslayer '\x07' "${name:0:15}"
fi
if [ "$pres" != "" ]; then # Reason for absence of name
	preslayer '\x08' $pres
fi
if [ "$messages" != "" ]; then # Network message system status (0x0B confirmed, https://www.microsemi.com/document-portal/doc_view/126509-msan164-appnote p.3)
	# https://stackoverflow.com/questions/6292645/convert-binary-data-to-hexadecimal-in-a-shell-script
	hexmessages=`printf '%02X' $messages | xxd -r -p` # binary encoded value, so convert that to hex first
	preslayer '\x0B' $hexmessages 1
fi

## seizure/mark should not be part of checksum or length computations, so write to a separate file
# Seizure = alternating 0 and 1 bits for 80-262 ms (96-315 bits) - pg. 11 https://web.archive.org/web/20080908040823/http://www.bell.cdn-telco.com/bid/BID-0001Multiple.pdf
# echo -e -n "\x55\x55\x55\x55\x55\x55\x55\x55\x55\x55\x55\x55\x55\x55\x55\x55" | xxd -p >> $pre # 128 bits of alternating 01010101...

# Note that there will be no channel seizure signal and the mark interval is only 70-90 bits. (pg. 4 - https://www.microsemi.com/document-portal/doc_view/126509-msan164-appnote)

# Mark  = 70-90 bits of mark
echo -e -n "\xFF\xFF\xFF\xFF\xFF\xFF\xFF\xFF\xFF\xFF" >> $pre # 80 bits of mark. This is the same number of bits as S.O.B. (Software Orange Box).

## Write to temp file
# Message Type word = 1 byte, x80 (128 decimal) indicates MDMF
printf '%b' '\x80' >> $text # Call Setup Msg. - Type 0x80

# Message Length word = 1 byte: sum of all presentation (starting with date...) - all the way to (but not including) checksum
echo -e -n $message >> $binary
length=`wc -c < $binary` # length excludes type/length/checksum bytes (i.e. "just the message") per pg. 8 https://www.ti.com/lit/an/bpra056/bpra056.pdf

# Message Length
printf '%02X' $length | xxd -r -p >> $text # convert hex string to literal hex

# Message - Presentation Layer (0-255)
cat $binary >> $text # convert ASCII to hex

# Checksum calculations: http://matthieu.benoit.free.fr/cid_dsp.htm
# checksum is everything right up until the checksum, starting from message type: sum all the hex words
sum=`cat $text | xxd -p -c 1 -u | paste -s -d + | echo "obase=16;ibase=16;$(cat -)" | bc`
modulo100=${sum: -2} # only want last 2 bytes, for modulo 0x100
checksum=`echo "obase=16;ibase=16;FF-$modulo100+01" | bc`

# Checksum (1 byte): 2C of all bytes from type -> end of msg. block. Carry ignored. Result must be 0.
echo -e -n $checksum | xxd -r -p >> $text

# 8-bit data words, with 1 start (space) bit and 1 stop (mark) bit: https://web.archive.org/web/20080908040823/http://www.bell.cdn-telco.com/bid/BID-0001Multiple.pdf pg. 12
# Least Significant Bit (LSB) TX first
cat $pre | minimodem --tx --startbits 0 --stopbits 0 -f $audio0 1200 # no stop bits or start bits, or otherwise we get logical 0s inserted between the (otherwise) continuous stream of 1s
cat $text | minimodem --tx --ascii -f $audio1 1200 # Caller ID is 1200 baud 8N1
sox --combine concatenate $audio0 $audio1 $audio # concatenate the mark interval and actual data together
sox $audio --rate 8000 --channels 1 --type ul $ulaw # convert to ulaw for G.711 playback
printf '%s' $ulaw # return ulaw audio file: calling application can play this and delete it
rm -rf $pre $binary $text $audio0 $audio1 # delete everything except the output audio files
rm -rf $audio # delete the output wav file since Asterisk only needs the ulaw file. If you want the final WAV file instead, comment this out
