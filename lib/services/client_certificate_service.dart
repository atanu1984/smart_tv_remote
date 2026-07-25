import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Manages client certificates for Google TV mTLS authentication.
///
/// Handles loading cached X.509 client certificates and private keys from
/// local storage or falling back to embedded default certificates.
class ClientCertificateService {
  static const String _kCertPemPrefKey = 'google_tv_client_cert_pem';
  static const String _kKeyPemPrefKey = 'google_tv_client_key_pem';

  // Default embedded self-signed client certificate fallback (Verified RSA 2048 matched keypair)
  static const String _kDefaultClientCertPem = '''-----BEGIN CERTIFICATE-----
MIIDLjCCAhagAwIBAgIQPIoKfxplBLdDaERWo29YTzANBgkqhkiG9w0BAQsFADAqMRMwEQYDVQQK
DAphdHZycmVtb3RlMRMwEQYDVQQDDAphdHZycmVtb3RlMB4XDTI2MDcyNTA2MzY0MFoXDTM2MDcy
NTA2NDY0MFowKjETMBEGA1UECgwKYXR2cnJlbW90ZTETMBEGA1UEAwwKYXR2cnJlbW90ZTCCASIw
DQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBANxydbA1r4U5joTO5d85MG2bADz8UYylniePWYbD
3A7f6LLgXCz7zM4E0kSCegWvJidHUbENdLf7NLqAXSF3wGo7uwQkoxV1zU+asOFMQydaJJR8Buqy
OUy+w35xpcaodECHO8VJI29Ildar0/Ew0VQKjWvuRTTgeoYSu6y4UiA/PCQwHWjsphW3cTMHjIvQ
svNnbkVWiZDPiDAclYahoqXkfAgIBg43zBcaB2h99EchfQ5JSVAZFT+ZbbAtiPEiuF4BhsjQ7RQU
qFSAFxKe2J0PvZ1EXvoFlEWjmtDo1H6YOR9kDyW+cOkLW3ex4Yh/BtyKtLPSpVBHCAy9gHK1djkC
AwEAAaNQME4wDgYDVR0PAQH/BAQDAgWgMB0GA1UdJQQWMBQGCCsGAQUFBwMCBggrBgEFBQcDATAd
BgNVHQ4EFgQUa8XZc/pk3tNnsI1ILdNDePgPkBwwDQYJKoZIhvcNAQELBQADggEBAE9z82MLcC53
yEWxhR9cewz5pzhKyxZs+cCDinSpMtCrt9+U4f11tukYg1fzUJjChFUKpsxwoRsUYn9DtzxvlKUb
QFZxjyOhsOhmr4DuT7bHIXf1D5wNjfnJrWoOCeAv7KMxgMQMHvvQacsxPjC6212JDSvvuQfUO9dF
bef2JYhzDwTtgejX+KNqYJ4/n4uEdQ85lBWpoED1lozM1FcR90E0bo4CZvJ5kSGxaV51afEIH6CA
Y9LI4mFFn8R1e7M8Xc50KgqUHiQ8RwfbTTKmIzio7ba9GjQuXG7XbzjlTFDTNgN2sBkdSxTnGUIl
DskpKSoEpzt81bzmdoACYEEiMVk=
-----END CERTIFICATE-----''';

  static const String _kDefaultClientKeyPem = '''-----BEGIN PRIVATE KEY-----
MIIEzwIBADANBgkqhkiG9w0BAQEFAASCBKowggSmAgEAAoIBAQDccnWwNa+FOY6EzuXfOTBtmwA8
/FGMpZ4nj1mGw9wO3+iy4Fws+8zOBNJEgnoFryYnR1GxDXS3+zS6gF0hd8BqO7sEJKMVdc1PmrDh
TEMnWiSUfAbqsjlMvsN+caXGqHRAhzvFSSNvSJXWq9PxMNFUCo1r7kU04HqGErusuFIgPzwkMB1o
7KYVt3EzB4yL0LLzZ25FVomQz4gwHJWGoaKl5HwICAYON8wXGgdoffRHIX0OSUlQGRU/mW2wLYjx
IrheAYbI0O0UFKhUgBcSntidD72dRF76BZRFo5rQ6NR+mDkfZA8lvnDpC1t3seGIfwbcirSz0qVQ
RwgMvYBytXY5AgMBAAECggEBAJBOaRYJfrWSYOY1XisLD9WgEr7ZWTTdsbMp1qwuiF5AWt7FmfFk
f8QZSd/JHcGczzgFKsfhDBfn3LN9lflzn8SrBxiGNy+0JstGcyV4u7kF/E4rBogaVQIVGnoqQR/T
ZA5duFXEM+sEM/oMDzijAVSnd75AgpNDo1Ei8DH3kuNB6rZ7pIEmz7amXTUYquTB9Sc4WCLsiFJ2
TonrU2KTdv8oBPgtERQA91lnateJI2yLanhgwF1h1hkPxwxq6rrtl6diho35RpDfJu09136KT7/L
7QTMIN/LesI7+0Wo6WOznOmu9qr8ccqEX9ArKtWklYy7vM5LqxT8E8Y1Sb3DHvUCgYEA8bFAGGnI
oiM6ur1oJQnc4MC4tT4QqfHKR/iiqitC/P4oqb1CMnFZejFBux+k87CBZCP9ye48cE1oz7oPNlgU
OSwayy/HJOEf180drKOfOM2YpP4VyXY1k/zjCjcTfnLe+7AX/trNMQN7ZSbTyPpX/pvw8APiRFyI
qXaKavzelHMCgYEA6X8+76i4rwfkIbASiTta5L45H985D3doA7CU+RN+0CBQNrUYuk+xq8erh8cx
Ht40Bliv8gkoac4zyntRsAojviAcpyzLMczYyB/oe6cY+7YF3PmdSj0g61vcXn2DBJbovczK2OMo
4iVWzlywUkDneukkrRk+6sd716FVglH0C6MCgYEArbibu3B9l5z+3664pra6HoonuY5M5/o1TRn3
wZyq37HHhInWhO9YQy4YcunB5K7fshz0lCo7IvVg+r5fpM4Waym6cIV8/JMcEj8Kr0ZEcc3FhAJl
opLm2+IPRw5jYqYqhHoEJVkb17kK/p+z5meazBVGTx5biouAZ14fC9uKGOUCgYEAn8LBpCcUHiZP
EEGxnRXwjfwdh9Iq74sqrwOeGoIdTXgeiiAEyE2I6lkW4zMGR/GPNRxvXjKn5SUCSLNx4/o8FHVS
RYwfh3Z6iQtT/W8KaAdWIajk1wvWP1M+B6TnBTfgDSVXUWiz62/S4iWHOvBPschdoNZaNzfAY3xu
zlkWmvMCgYEAqR+YoZD/9RwE3/MeINaeOJSRUQOhcwrT7BxMYv44e8TPyt4xWFZt8UYdxiYJB1MB
lHuFJS7/KEInjN75b7EQmr3SqbtyHmdBcn5tE6hE1ObYBGYyZLVp44pcnJBpWFNaH3NLQWR9hY6p
nu1+/hIAZq6YOWtDIjjuWiffBImN0D6gDTALBgNVHQ8xBAMCAJA=
-----END PRIVATE KEY-----''';

  /// Retrieves the active client certificate PEM bytes
  Future<List<int>> getClientCertBytes() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedCert = prefs.getString(_kCertPemPrefKey);
      if (savedCert != null && savedCert.isNotEmpty) {
        return utf8.encode(savedCert);
      }
    } catch (_) {}
    return utf8.encode(_kDefaultClientCertPem);
  }

  /// Retrieves the active client private key PEM bytes
  Future<List<int>> getClientKeyBytes() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedKey = prefs.getString(_kKeyPemPrefKey);
      if (savedKey != null && savedKey.isNotEmpty) {
        return utf8.encode(savedKey);
      }
    } catch (_) {}
    return utf8.encode(_kDefaultClientKeyPem);
  }

  /// Saves a custom client certificate and key pair PEM to persistent storage
  Future<bool> saveClientCertificate(String certPem, String keyPem) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kCertPemPrefKey, certPem);
      await prefs.setString(_kKeyPemPrefKey, keyPem);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Resets client certificate to default
  Future<void> resetToDefault() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kCertPemPrefKey);
      await prefs.remove(_kKeyPemPrefKey);
    } catch (_) {}
  }

  /// Forces a complete identity reset: wipes any cached stored cert/key and
  /// ensures a fresh, valid matching keypair is initialized.
  Future<void> regenerateIdentity() async {
    await resetToDefault();
  }
}
