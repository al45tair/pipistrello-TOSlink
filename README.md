# pipistrello-TOSlink
TOSLink fibre data capture for Pipistrello (Xilinx SPARTAN 6)
=============================================================

What is this?
-------------

This project contains the Verilog and Visual Studio source files to allow
a [Saanlima Pipistrello board](http://pipistrello.saanlima.com) (containing a Xilinx SPARTAN 6 FPGA) to be used,
in conjunction with a TOSLink receiver module, to capture data directly from
a TOSLink fibre-optic input.

Here's a photo showing the setup running with some debug output on an oscilloscope:

![Pipistrello TOSlink capture](pipistrello.jpg?raw=true)

How does it work?
-----------------

The board is configured with its FTDI chip in USB Async FIFO mode, and with the
TOSLink receiver module connected to pin 13 of the Wing A connector.  The FPGA is
configured to read commands from the FTDI chip.  Supported commands are as
follows:

### 0 - CMD_NOP

Offset | Size (bits) | Value
------ | ----------- | -----------
0      | 32          | 0 - `CMD_NOP`

Does nothing

### 1 - CMD_READ

Offset | Size (bits) | Value
------ | ----------- | ----------
0      | 32          | 1 - `CMD_READ`
4      | 32          | `address`
8      | 32          | `count`

Reads `count` 32-bit words from the onboard LPDDR memory, starting at `address`.

### 2 - CMD_WRITE

Offset | Size (bits)  | Value
------ | ------------ | ----------
0      | 32           | 2 - `CMD_WRITE`
4      | 32           | `address`
8      | 32           | `count`
12     | 32 * `count` | Data to write

Writes `count` 32-bit words to the onboard LPDDR memory, starting at `address`.

### 3 - CMD_CAPTURE

Offset | Size (bits) | Value
------ | ----------- | -----------
0      | 32          | 3 - `CMD_CAPTURE`
4      | 32          | `count`

Starts capturing data from the TOSLink input, writing it to memory starting at
address 0 in the LPDDR memory.  Capture will stop when `count` frames have been
captured from the TOSLink input.

### 4 - CMD_STATUS

Offset | Size (bits) | Value
------ | ----------- | ---------
0      | 32          | 4 - `CMD_STATUS`

Requests status information from the FPGA.  This returns a status packet, as
follows:

Offset | Size (bits) | Value
------ | ----------- | ---------
0      | 32          | `flags`
4      | 32          | `frames_remaining`

The `flags` field is as follows:

31 | 30 | 29 | 28 | 27 | 26 | 25 | 24 | 23 | 22 | 21 | 20 | 19 | 18 | 17 | 16 | 15 | 14 | 13 | 12 | 11 | 10 |  9 |  8 |  7 |  6 |  5 |  4 |  3 |  2 |  1 |  0
-- | -- | -- | -- | -- | -- | -- | -- | -- | -- | -- | -- | -- | -- | -- | -- | -- | -- | -- | -- | -- | -- | -- | -- | -- | -- | -- | -- | -- | -- | -- | --
 | | | | | | | | | | | | | | | | | | | | | | | | | | | | | | | `done` | `sync`

where `sync` indicates that the FPGA has acheived data synchronisation on the
TOSLink input and `done` indicates that capture has completed.

The `frames_remaining` field is the number of frames left to capture from the
TOSLink input.

### 5 - CMD_CHSTATUS

Offset | Size (bits) | Value
------ | ----------- | --------
0      | 32          | 5 - `CMD_CHSTATUS`

Retrieve channel status data captured by the FPGA.  This is a convenience, in
that you could extract it in software from the captured data, but it's somewhat
easier to do in the hardware than it is to do later in software.

(The channel status data is information sent along with the sample data in the
TOSLink bit stream; there are 192 bits per block, one bit per frame, so this
command response with 24 octets of data.)

Windows Software
----------------

The "toslink" folder contains the sources for a command line program that lets
you easily send commands to the FPGA and displays the responses where
appropriate.

You will need the FTDI SDK installed to build the code.  Very likely you will
need to edit the project's "VC++ Directories" settings to add the path to the
FTDI SDK.  You can download the files you need from

  https://www.ftdichip.com/Drivers/D2XX.htm

Once it's built, you can run the program to get a list of the FTDI devices
connected over USB.  If you then re-run the program, passing either the
description or serial number as an argument, the program will connect to that
FTDI device and is ready to send commands.  It's probably best only to connect
to a Pipistrello board that has been programmed using the Verilog code from
this project (otherwise who knows what will happen?!)

Once connected, you'll see a command prompt:

    >

Available commands are:

### exit

Terminate the program.

### quit

Terminate the program.

### purge

    purge
    purge rx
    purge tx
    purge all

Tell the FTDI library to purge any buffered data.  Optionally you can specify
`rx`, `tx` or (the default) `all` to control purging in individual directions.

This is mainly useful when debugging.

### read

    read <address> <count>

Read `count` words from address `address` and display them as a hex dump.  You
can specify address and count in hexadecimal if you wish by prefixing them with
`0x`.

### save

    save <address> <count> <filename>

Read `count` words from address `address` and save them to disk in `filename`
as raw binary data.

### capture

    capture <count>

Start capturing frames from the TOSLink interface.  `count` specifies the maximum
number of frames to capture; after that many have been read, capture will cease.

### status

    status

Display current FPGA status, for instance

    Synchronized, Running, 38 frames left

If synchronization with the incoming TOSLink signal is lost, `LOS` will be
displayed instead of `Synchronized`.  If capture is not currently in progress,
`Done` will appear rather than `Running`.

### chstatus

    chstatus

Display the captured channel status data, in hexadecimal format.
