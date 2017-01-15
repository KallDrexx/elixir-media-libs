# Elixir Media Libs

The Elixir Media Libs is a collection of libraries and applications written in that that revolve around working with media.  

This project currently contains the following systems:
* **amf0** - Library providing functionality for serializing and deserializing values with the AMF0 data format.
* **amf3** - **INCOMPLETE** Library providing functionality for serializing and deserializing values with the AMF3 data format.
* **flv** - **INCOMPLETE** Library providing functionality for reading FLV media files and streams
* **rtmp** - Library providing functionality for handling RTMP handshakes, protocol (de)serialization, and low level/expandable server handling (with client handling coming soon)
* **gen_rtmp_server** - A generic behaviour for building your own custom RTMP server
* **simple_rtmp_server** - An example RTMP server built upon the `gen_rtmp_server` library, for testing and reference purposes.  
* **rtmp_reader_cli** - A command line application for reading raw RTMP chunk byte streams from a file.  Mostly utilized to debug input and output dumps generated from the raw I/O logging mechanisms of a `rtmp_session`.