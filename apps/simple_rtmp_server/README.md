# SimpleRtmpServer

The simple RTMP server is a very basic example of a `GenRtmpServer` implementation.  It is meant to test the publication and playback of a server with very little logic surrounding it.  It therefore accepts all RTMP requests and takes very little actions on top of it besides routing audio, video, and metadata values between connected publishers and players.

Starting a server on port 1935 is as simple as running:

`mix run --no-halt`