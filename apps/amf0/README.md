# Amf0

Provides functions to serialize and deserialize data encoded in the AMF0 data format based on the official (Adobe Specification)[http://wwwimages.adobe.com/content/dam/Adobe/en/devnet/amf/pdf/amf0-file-format-specification.pdf].  

This library so far implements basic types required for RTMP communication and thus currently supports:
* numbers
* booleans
* UTF8 strings
* Nulls
* Arrays
* Objects with properties

## Examples

```
iex> Amf0.deserialize(<<0::8, 532::float-64, 1::8, 1::8>>)
{:ok, [532.0, true]}

iex> Amf0.serialize("test")
<<2::8, 4::16>> <> "test"

iex> Amf0.serialize([532, true])
<<0::8, 532::float-64, 1::8, 1::8>>
```