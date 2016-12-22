# RtmpReaderCli

Utility for parsing raw RTMP chunk binary file.  It will go through the binary one RTMP message at a time and provide output useful for debugging an RTMP workflow.

Each input file should only contain one direction of the stream (input or output), should not contain any bytes from the handshake, and should start from the first byte after the handshake (otherwise non-type 0 RTMP chunks may not resolve properly).

This was made for use in debugging raw I/O dumps created by the `rtmp_session` module.