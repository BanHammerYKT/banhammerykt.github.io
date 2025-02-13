function FindProxyForURL(url, host) {
  if (dnsDomainIs(host, "jetbrains.com")) return "PROXY 192.168.1.110:5353";
  if (dnsDomainIs(host, "codeium.com")) return "PROXY 192.168.1.110:5353";
  return "DIRECT";
}
