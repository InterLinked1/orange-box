# orange-box
Flexible Orange Box (Type II Caller ID Generator)

## Background

This is **F.O.B. (Flexible Orange Box)**, inspired by the popular S.O.B. (Software Orange Box) program for Windows.

### *Update*

*If you are looking for an orange box for Asterisk*, you should consider this program *superseded* by the native Asterisk module [`app_callerid`](https://github.com/InterLinked1/phreakscript/blob/master/apps/app_callerid.c). You can use the `SendCWCID` application to automatically handle the entire Type II Caller ID generation process, without having to deal with system calls, external files, etc. It's a much nicer solution!

If you install Asterisk using [PhreakScript](https://github.com/InterLinked1/phreakscript), you will automatically get the `app_callerid` module and the `SendCWCID` application.

F.O.B. is still a generic orange box that can be used for anything, not just Asterisk, so this program is still maintained, just *not recommended if you are using Asterisk* since there is something better for that now.

#### Problem

When connecting SIP FXS devices with a Class 5 switch, the ATA will not see a Call Waiting presented to it when there is a Call Waiting. Thus, it is necessary to signal the FSK directly to the CPE in-band from the switch. Asterisk does not have any provision to do this, so this needs to be done with an external program.

#### Solution

I was looking for a Type II Caller ID generator that I could use in conjunction with Asterisk for the purposes of generating Type II Caller ID ("Call Waiting Caller ID"). Not finding any, and also frustrated by the lack of Caller ID generators that implement the complete Multiple Data Message Format (MDMF), I decided to write my own program that was capable of generating all the presentation layers, not just the most popular ones.

This program is intended to be a legitimate Type II Caller ID Generator, used for the purpose of Call Waiting Caller ID (Of course, functionally, it can be used just like any other orange box to spoof call waitings if desired - we are not responsible for any misuse of this program). This allows you to send Call Waiting Caller ID to a remote endpoint, even if no Call Waiting is presented to the remote endpoint (e.g. Analog Telephone Adapter), allowing for CWCID to be provided even when advanced bridging capabilites are being used, by "orange boxing" in band for legitimate purposes.

#### Why?

Great question. Most Caller ID units only support Time/Date, Calling Number, and Calling Name (and presentation, of course). However, this is just a small part of the full specification. The [BellSouth CI7112 Visual Director](https://www.amazon.com/BellSouth-Caller-Waiting-Deluxe-CI-7112/dp/B00RZK7UVK/), for instance, has the capability of letting you know the redirecting status of a call (such as if the number called was busy or didn't answer) *and* if the call is long distance. Yet, most Caller ID generators complete ignore these properties.

Most Caller ID units will simply ignore parameters they do not support (this is what they're *supposed* to do, at least...). However, for the optional/additional parameters, not supplying an argument or supplying an empty argument will cause that parameter to not be sent, so you can prevent the transmission of these parameters as desired. That's why this is called the **Flexible Orange Box**. It's Caller ID, *your* way. This script is designed to be flexible, without making too many assumptions about the Caller ID parameters. It does assume that you want the correct time but does let you set the time zone.

## Usage

#### What this program does
This Type II Caller ID generator generates the exact binary data that is sent to the Caller ID unit. This script then invokes minimodem to actually turn this into 1200 baud FSK audio. This program is optimized to be used directly with Asterisk, and can be invoked using the `${SHELL}` function.

#### What this program doesn't do
This *doesn't* generate either the Subscriber Alerting Signal (i.e. "Call Waiting Tone") or the CPE Alerting Signal (Customer Premises Equipment Alerting Signal). The SAS is typically 440 Hz for 300ms. However, it can be different with Distinctive Call Waiting, and technically, you might not need to provide it at all. The purpose of the SAS is to let the called party know that he has a call waiting. This signal is repeated once every ten seconds until either the caller hangs up or the called party attends to the call waiting in some way (not necessarily answering it, since Call Waiting Deluxe lets you do other things).

The CAS is the important part. It's 2130+2750 Hz for about 80-85ms. The signal should end cleanly. If there is echo afterwards, it won't work. In Asterisk, you can play a dummy tone or quick audio file to suppress any echo that occurs if audio is not followed up immediately with more audio.

TL;DR - this script doesn't generate the SAS or the CAS. That is your responsibility, but you can do this easily in Asterisk.

#### System Requirements

I wrote and tested this in Debian 10 (non-GUI), but as a Bash script, it should run in most any Linux environment.

Some pre-requisites include:
- minimodem (FSK generation)
- bc (hex math)
- sox (audio manipulation and conversion)

#### Arguments

This program accepts 8 arguments:

Recommended/Mandatory Arguments:
- 1: **Time Zone** - If an empty argument is provided, this defaults to the system time zone.
- 2: **Caller Number** - `${CALLERID(num)}` or `${CALLERID(ANI-num)}` should be provided, *regardless of the presentation*. If more than 15 characters are passed in, the script will truncate the CNAM to the first 15 characters.
- 3: **Caller Name** - `${CALLERID(name)}` should be provided, *regardless of the presentation*
- 4: **Caller Presentation** - `${CALLERID(pres)}`

Optional Arguments (if not specified, these parameters will not be sent):
- 5: **Redirecting Number** - `${CALLERID(RDNIS)}`
- 6: **Redirecting Reason** - `${REDIRECTING(reason)}`
- 7: **Call Qualifier ("Long Distance Call")** - 1 for long distance, 0 or empty otherwise
- 8: **Number of Messages** - 0 or positive integer representing # of messages waiting if this parameter is sent

Apart from the Call Qualifier, Time Zone, and # Messages Waiting, all the arguments are standard Asterisk channel variables you can simply pass in. The rest can be computed or calculated as desired.

#### Return Value

This program returns the full path to the generated audio file containing 1200 baud (Bell 202) FSK. It is your responsibility to play the file and then delete it from your invoking program (e.g. Asterisk).

## Support

This program has been tested and working with some CPE, but of course, it's impossible to test them all. If you experience issues or the program does not work as described, please report these and we can try to look into them. No guarantees are provided and all support is provided on an "as is" / "as able" basis.
