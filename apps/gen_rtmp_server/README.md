# GenRtmpServer

`GenRtmpServer` is a behaviour that allows developers to easily implement custom RTMP servers without worrying about the underlying protocol or internal RTMP workflows (such as chunk sizes).  
 
 It will trigger functions in modules that implement the behaviour when any events occur that may need application specific workflows, such as if a connection should be accepted or rejected, if a connection should be allowed to publish or play video on a specific stream key, or even when audio and video data is received.  
 
 It also contains functions for sending RTMP messages back to clients as an application determines it is needed.