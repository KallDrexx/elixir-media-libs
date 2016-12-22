# RtmpSession

An RTMP session is an abstraction representing a single peer in an RTMP connection.  Raw bytes from the RTMP stream get passed in and the `RtmpSession` abstraction returns bytes it should send to the other peer or any events that need to be handled.  

For example, if the RTMP session is a server and a client connects to it, the client will send over a stream of bytes representing an RTMP chunk containing a connection request message.  When those bytes are passed into the RTMP session it will return bytes representing RTMP bytes for data it should send immediately (chunk size, window acknowledgement size, etc...) as well as returning an event that the client is requesting a connection on a specific application.

The system utilizing the RTMP session is then free to look at the connection requested event and decide if the connection should be allowed.  It then tells the rtmp session that the connection request was accepted or rejected, and the RTMP session will produce outbound bytes and subsequent events if any.

An RTMP session expects that it is the sole receiver and producer of all input and output bytes for the connection, and has received every byte after the handshake.  This is due to the way the RTMP protocol tries to compress RTMP chunks, and not following this will cause mis-compression of headers and most likely crashes for the session or the peer (due to corrupt input).