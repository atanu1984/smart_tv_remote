enum TvBrand {
  roku,
  samsung,
  lg,
  androidTv,
  tcl,
  genericDial,
}

extension TvBrandExtension on TvBrand {
  String get displayName {
    switch (this) {
      case TvBrand.roku:
        return 'Roku TV';
      case TvBrand.samsung:
        return 'Samsung Smart TV';
      case TvBrand.lg:
        return 'LG webOS TV';
      case TvBrand.androidTv:
        return 'Android / Google TV';
      case TvBrand.tcl:
        return 'TCL Google TV';
      case TvBrand.genericDial:
        return 'Smart TV (DIAL/UPnP)';
    }
  }

  String get defaultIconName {
    switch (this) {
      case TvBrand.roku:
        return 'tv_roku';
      case TvBrand.samsung:
        return 'tv_samsung';
      case TvBrand.lg:
        return 'tv_lg';
      case TvBrand.androidTv:
        return 'tv_android';
      case TvBrand.tcl:
        return 'tv_tcl';
      case TvBrand.genericDial:
        return 'tv_generic';
    }
  }
}

class SmartTvDevice {
  final String id;
  final String originalName;
  final String? customName;
  final TvBrand brand;
  final String ipAddress;
  final int port;
  final String? modelName;
  final String? manufacturer;
  final String? serialNumber;
  final String discoveryMethod;
  final DateTime lastSeen;
  final bool isOnline;

  const SmartTvDevice({
    required this.id,
    required String name,
    this.customName,
    required this.brand,
    required this.ipAddress,
    required this.port,
    this.modelName,
    this.manufacturer,
    this.serialNumber,
    required this.discoveryMethod,
    required this.lastSeen,
    this.isOnline = true,
  }) : originalName = name;

  String get name => (customName != null && customName!.trim().isNotEmpty) ? customName! : originalName;

  SmartTvDevice copyWith({
    String? id,
    String? name,
    String? customName,
    TvBrand? brand,
    String? ipAddress,
    int? port,
    String? modelName,
    String? manufacturer,
    String? serialNumber,
    String? discoveryMethod,
    DateTime? lastSeen,
    bool? isOnline,
  }) {
    return SmartTvDevice(
      id: id ?? this.id,
      name: name ?? this.originalName,
      customName: customName ?? this.customName,
      brand: brand ?? this.brand,
      ipAddress: ipAddress ?? this.ipAddress,
      port: port ?? this.port,
      modelName: modelName ?? this.modelName,
      manufacturer: manufacturer ?? this.manufacturer,
      serialNumber: serialNumber ?? this.serialNumber,
      discoveryMethod: discoveryMethod ?? this.discoveryMethod,
      lastSeen: lastSeen ?? this.lastSeen,
      isOnline: isOnline ?? this.isOnline,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'originalName': originalName,
      'customName': customName,
      'brand': brand.name,
      'ipAddress': ipAddress,
      'port': port,
      'modelName': modelName,
      'manufacturer': manufacturer,
      'serialNumber': serialNumber,
      'discoveryMethod': discoveryMethod,
      'lastSeen': lastSeen.toIso8601String(),
      'isOnline': isOnline,
    };
  }

  factory SmartTvDevice.fromJson(Map<String, dynamic> json) {
    return SmartTvDevice(
      id: json['id'] as String,
      name: (json['originalName'] ?? json['name']) as String,
      customName: json['customName'] as String?,
      brand: TvBrand.values.firstWhere(
        (b) => b.name == json['brand'],
        orElse: () => TvBrand.genericDial,
      ),
      ipAddress: json['ipAddress'] as String,
      port: json['port'] as int,
      modelName: json['modelName'] as String?,
      manufacturer: json['manufacturer'] as String?,
      serialNumber: json['serialNumber'] as String?,
      discoveryMethod: json['discoveryMethod'] as String? ?? 'auto',
      lastSeen: DateTime.parse(json['lastSeen'] as String),
      isOnline: json['isOnline'] as bool? ?? true,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SmartTvDevice &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}
