# Elixir Media Libs

The Elixir Media Libs is a collection of libraries and applications written in that that revolve around working with media.  

This project currently contains the following systems:
* **amf0** - Library providing functionality for serializing and deserializing values with the AMF0 data format.
* **amf3** - **INCOMPLETE** Library providing functionality for serializing and deserializing values with the AMF3 data format.
* **flv** - **INCOMPLETE** Library providing functionality for reading FLV media files and streams
* **rtmp_handshake** - Library providing functionality for handling the RTMP handshake process as either the client or the server.  Supports both simple and digest types of handshakes.
* **rtmp_session** - Library representing an abstraction of a single RTMP workflow, abstracting away handling of incoming and outgoing RTMP chunks and messages and providing a consumer friendly way of building a system on top of the RTMP protocol.
* **gen_rtmp_server** - A generic behaviour for building your own custom RTMP server
* **simple_rtmp_server** - An example RTMP server built upon the `gen_rtmp_server` library, for testing and reference purposes.  
* **rtmp_reader_cli** - A command line application for reading raw RTMP chunk byte streams from a file.  Mostly utilized to debug input and output dumps generated from the raw I/O logging mechanisms of a `rtmp_session`.