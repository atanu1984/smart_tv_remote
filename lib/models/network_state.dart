class NetworkState {
  final bool isConnectedToWifi;
  final String? wifiSsid;
  final String? localIp;
  final String? subnetPrefix; // e.g. "192.168.1"
  final bool isScanning;
  final String? scanStatusMessage;

  const NetworkState({
    this.isConnectedToWifi = false,
    this.wifiSsid,
    this.localIp,
    this.subnetPrefix,
    this.isScanning = false,
    this.scanStatusMessage,
  });

  NetworkState copyWith({
    bool? isConnectedToWifi,
    String? wifiSsid,
    String? localIp,
    String? subnetPrefix,
    bool? isScanning,
    String? scanStatusMessage,
  }) {
    return NetworkState(
      isConnectedToWifi: isConnectedToWifi ?? this.isConnectedToWifi,
      wifiSsid: wifiSsid ?? this.wifiSsid,
      localIp: localIp ?? this.localIp,
      subnetPrefix: subnetPrefix ?? this.subnetPrefix,
      isScanning: isScanning ?? this.isScanning,
      scanStatusMessage: scanStatusMessage ?? this.scanStatusMessage,
    );
  }
}
