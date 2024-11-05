import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:bluetooth_print/bluetooth_print.dart';
import 'package:bluetooth_print/bluetooth_print_model.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'widgets/snackBarCustom.dart';
import 'widgets/roundedCheckbox.dart';
import 'dart:ui' as ui;

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'In thẻ điện thoại',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const PrinterPage(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class PrinterPage extends StatefulWidget {
  const PrinterPage({super.key});

  @override
  State<PrinterPage> createState() => _PrinterPageState();
}

class ConnectedDeviceManager {
  static BluetoothDevice? _lastConnectedDevice;

  static void setConnectedDevice(BluetoothDevice? device) {
    _lastConnectedDevice = device;
  }

  static BluetoothDevice? getConnectedDevice() {
    return _lastConnectedDevice;
  }

  static void clear() {
    _lastConnectedDevice = null;
  }
}

class _PrinterPageState extends State<PrinterPage> with WidgetsBindingObserver {
  BluetoothPrint bluetoothPrint = BluetoothPrint.instance;
  List<BluetoothDevice> _devices = [];
  BluetoothDevice? _selectedDevice;
  String _deviceMsg = "";
  String _selectedProvider = 'Viettel';
  String _selectedDenomination = '20.000 VND';
  bool _isConnected = false;
  bool _isSearching = false;
  bool _showExitWarning = false;
  bool _printWithQR = false;
  int backButtonPressCount = 0;
  DateTime? _lastBackPress;
  Timer? _searchTimer;
  Timer? _exitWarningTimer;
  final int backButtonThreshold = 2;
  final TextEditingController _textContent = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final Map<String, List<String>> _providerDenominations = {
    'Viettel': [
      '20.000 VND',
      '30.000 VND',
      '50.000 VND',
      '100.000 VND',
      '200.000 VND',
      '300.000 VND',
      '500.000 VND',
      '1.000.000 VND'
    ],
    'Vinaphone': [
      '20.000 VND',
      '30.000 VND',
      '50.000 VND',
      '100.000 VND',
      '200.000 VND',
      '300.000 VND',
      '500.000 VND',
      '1.000.000 VND'
    ],
    'Mobifone': [
      '20.000 VND',
      '30.000 VND',
      '50.000 VND',
      '100.000 VND',
      '200.000 VND',
      '300.000 VND',
      '500.000 VND',
      '1.000.000 VND'
    ],
  };
  late StreamSubscription _bluetoothStateDialog;
  Uint8List? _previewImage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this); // Thêm observer
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this); // Xóa observer
    _focusNode.dispose();
    _searchTimer?.cancel();
    _exitWarningTimer?.cancel();
    bluetoothPrint.disconnect();
    _bluetoothStateDialog.cancel();
    ConnectedDeviceManager.clear();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed &&
        !_isConnected &&
        _selectedDevice != null) {
      //await _connectBluetooth();
      // } else if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      //   await _disconnectBluetooth();
    }
  }

  void _listenToBluetoothState(StateSetter setDialogState) {
    _bluetoothStateDialog = bluetoothPrint.state.listen((state) {
      setState(() {
        if (state == BluetoothPrint.CONNECTED) {
          _isConnected = true;
        } else if (state == BluetoothPrint.DISCONNECTED) {
          _isConnected = false;
          _selectedDevice = null;
          ConnectedDeviceManager.clear();
          _searchDevices();
          _updateStatus();
        }
      });
      setDialogState(() {});
      setState(() {});
    });
  }

  Future<void> _connectBluetooth() async {
    if (_selectedDevice == null) {
      setState(() {
        _deviceMsg = 'Hãy chọn máy in để kết nối';
      });
      if (!mounted) return;
      showTopSnackBar(context, 'Chưa chọn thiết bị');
      return;
    }

    try {
      setState(() {
        _deviceMsg = 'Đang kết nối...';
      });

      await bluetoothPrint.connect(_selectedDevice!);
      await Future.delayed(const Duration(milliseconds: 500));

      setState(() {
        _isConnected = true;
        ConnectedDeviceManager.setConnectedDevice(_selectedDevice);
        _updateStatus();
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted) {
            Navigator.of(context).pop();
          }
        });
        showTopSnackBar(context, 'Đã kết nối với: ${_selectedDevice!.name}');
      });
    } catch (e) {
      setState(() {
        _isConnected = false;
        if (kDebugMode) {
          print("Lỗi kết nối: $e");
        }
      });
      if (!mounted) return;
      showTopSnackBar(context, 'Lỗi kết nối !');
    }
  }

  Future<void> _disconnectBluetooth() async {
    try {
      await bluetoothPrint.disconnect();

      setState(() {
        _isConnected = false;
        _selectedDevice = null;
        ConnectedDeviceManager.clear();
        _updateStatus();
      });
    } catch (e) {
      if (kDebugMode) {
        print("Lỗi khi ngắt kết nối: $e");
      }
      if (!mounted) return;
      showTopSnackBar(context, 'Lỗi khi ngắt kết nối !');
    }
  }

  void _updateStatus() {
    if (!mounted) return;
    setState(() {
      if (_isConnected && _selectedDevice != null) {
        _deviceMsg = 'Đã kết nối với ${_selectedDevice!.name}';
      } else {
        _deviceMsg = 'Chưa kết nối tới máy in';
      }
    });
  }

  Future<void> _searchDevices() async {
    if (!mounted) return;

    if (!_isConnected) {
      ConnectedDeviceManager.clear();
      _selectedDevice = null;
    }
    setState(() {
      _isSearching = true;
      _deviceMsg = 'Đang tìm kiếm...';
    });

    try {
      await bluetoothPrint.startScan(timeout: const Duration(seconds: 4));
      _searchTimer?.cancel();
      _searchTimer = Timer(const Duration(seconds: 0), () {
        if (mounted) {
          setState(() {
            _isSearching = false;
            _deviceMsg = _devices.isEmpty
                ? 'Không tìm thấy thiết bị'
                : 'Tìm thấy ${_devices.length} thiết bị';
          });
        }
      });
      // Lắng nghe kết quả scan và cập nhật UI ngay lập tức
      bluetoothPrint.scanResults.listen((devices) {
        setState(() {
          _devices = devices;

          // Thêm thiết bị đã kết nối vào danh sách nếu không có
          final connectedDevice = ConnectedDeviceManager.getConnectedDevice();
          if (connectedDevice != null && !devices.contains(connectedDevice)) {
            _devices = [...devices, connectedDevice];
          }

          // Cập nhật message dựa trên số lượng thiết bị tìm thấy
          _deviceMsg = _devices.isEmpty
              ? 'Đang tìm kiếm thiết bị...'
              : 'Đã tìm thấy ${_devices.length} thiết bị';
        });
      });
    } catch (e) {
      setState(() {
        _isSearching = false;
        _deviceMsg = "Hãy bật BLUETOOTH";
        showTopSnackBar(context, 'BLUETOOTH chưa được bật');
        if (kDebugMode) {
          print("Lỗi khi tìm kiếm: $e");
        }
      });
    }
  }

  void showTopSnackBar(BuildContext context, String message) {
    final overlay = Overlay.of(context);
    final overlayEntry = OverlayEntry(
      builder: (context) => TopSnackBar(message: message),
    );

    // Thêm widget vào overlay
    overlay.insert(overlayEntry);

    // Xóa widget khỏi overlay sau khi animation kết thúc
    Future.delayed(const Duration(seconds: 3), () {
      overlayEntry.remove();
    });
  }

// Định dạng số thẻ theo nhà mạng
  String formatCardNumber(String number, String provider) {
    if (number.isEmpty) return '';

    // Loại bỏ khoảng trắng và ký tự đặc biệt
    number = number.replaceAll(RegExp(r'[^0-9]'), '');

    switch (provider.toLowerCase()) {
      case 'viettel':
        // Format: xxx xxxx xxxx x (13 số)
        if (number.length == 13) {
          return '${number.substring(0, 3)} ${number.substring(3, 7)} ${number.substring(7, 11)} ${number.substring(11)}';
        }
        // Format: xxxx xxxx xxxx xxx (15 số)
        if (number.length == 15) {
          return '${number.substring(0, 4)} ${number.substring(4, 8)} ${number.substring(8, 12)} ${number.substring(12)}';
        }
        break;
      case 'vinaphone':
        // Format: xxxx xxxx xxxx xx (14 số)
        if (number.length == 14) {
          return '${number.substring(0, 4)} ${number.substring(4, 8)} ${number.substring(8, 12)} ${number.substring(12)}';
        }
        break;
      case 'mobifone':
        // Format: xxxx xxxx xxxx (12 số)
        if (number.length == 12) {
          return '${number.substring(0, 4)} ${number.substring(4, 8)} ${number.substring(8)}';
        }
        break;
    }
    return number; // Trả về số gốc nếu không match với format nào
  }

// Kiểm tra độ dài số thẻ theo nhà mạng
  bool isValidCardNumber(String number, String provider) {
    number = number.replaceAll(RegExp(r'[^0-9]'), '');

    switch (provider.toLowerCase()) {
      case 'viettel':
        return number.length == 13 || number.length == 15;
      case 'vinaphone':
        return number.length == 14;
      case 'mobifone':
        return number.length == 12;
      default:
        return false;
    }
  }

  Map<String, String> extractCardInfo(String text) {
    // Khởi tạo map để lưu kết quả
    Map<String, String> result = {
      'rechargeCode': '',
      'serialNumber': '',
    };

    // Tách các dòng
    List<String> lines = text.split('\n');

    // Duyệt qua từng dòng để tìm thông tin
    for (String line in lines) {
      // Tìm mã nạp
      if (line.toLowerCase().contains('mã nạp:') ||
          line.toLowerCase().contains('mã thẻ:') ||
          line.toLowerCase().contains('ma nap:') ||
          line.toLowerCase().contains('ma the:') ||
          line.toLowerCase().contains('mathe:') ||
          line.toLowerCase().contains('manap:') ||
          line.toLowerCase().contains('mã nap:') ||
          line.toLowerCase().contains('ma nạp:') ||
          line.toLowerCase().contains('mã the:') ||
          line.toLowerCase().contains('ma thẻ:')) {
        result['rechargeCode'] = line.split(':')[1].trim();
      }
      // Tìm số seri
      if (line.toLowerCase().contains('số seri:') ||
          line.toLowerCase().contains('số serial:') ||
          line.toLowerCase().contains('so seri:') ||
          line.toLowerCase().contains('so serial:') ||
          line.toLowerCase().contains('soseri:') ||
          line.toLowerCase().contains('soserial:')) {
        result['serialNumber'] = line.split(':')[1].trim();
      }
    }

    return result;
  }

// Hàm kiểm tra và xử lý thông tin thẻ
  Map<String, dynamic> validateAndFormatCardInfo(String text, String provider) {
    Map<String, String> cardInfo = extractCardInfo(text);
    String rechargeCode = cardInfo['rechargeCode'] ?? '';
    String serialNumber = cardInfo['serialNumber'] ?? '';

    Map<String, dynamic> result = {
      'isValid': true,
      'message': '',
      'rechargeCode': '',
      'serialNumber': '',
    };

    // Kiểm tra xem đã có đủ thông tin chưa
    if (rechargeCode.isEmpty || serialNumber.isEmpty) {
      result['isValid'] = false;
      result['message'] = 'Vui lòng nhập đầy đủ mã nạp và số seri';
      showTopSnackBar(context, 'Vui lòng nhập đầy đủ mã nạp và số seri');
      return result;
    }

    // Kiểm tra độ dài mã thẻ
    if (!isValidCardNumber(rechargeCode, provider)) {
      result['isValid'] = false;
      result['message'] = 'Mã nạp không hợp lệ cho nhà mạng $provider';
      showTopSnackBar(context, 'Mã nạp không hợp lệ cho nhà mạng $provider');
      return result;
    }

    // Format mã thẻ và số seri
    result['rechargeCode'] = formatCardNumber(rechargeCode, provider);
    result['serialNumber'] = formatCardNumber(serialNumber, provider);

    return result;
  }

  // End Format number and serial card
  Future<void> _launchUSSD(String code) async {
    // Định dạng USSD URI
    final uri = Uri.parse('tel:${code.replaceAll('#', '%23')}');

    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      throw 'Không thể mở mã USSD $code';
    }
  }

  Future<Uint8List> _createImageFromText(String text) async {
    final validationResult = validateAndFormatCardInfo(text, _selectedProvider);
    if (!validationResult['isValid']) {
      throw Exception(validationResult['message']);
    }

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final paint = Paint()..color = Colors.white;

    final rechargeCode = validationResult['rechargeCode'];
    final serialNumber = validationResult['serialNumber'];

    // Tạo chuỗi USSD từ mã nạp
    final ussdCode = '*100*${rechargeCode.replaceAll(' ', '')}#';

    final now = DateTime.now();
    final formattedDate =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')} ${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}';

    // Store information
    const storeName = "CỬA HÀNG HOÀNG DIỆU";
    const storePhone = "0987-390-432";
    const storeAddress = "Chợ Nhà Ngang, Hòa Chánh, UMT, KG";
    const datePrint = "Thời gian:";

    // Receipt content
    const serviceName = "Loại thẻ:";
    final serviceValue = _selectedProvider;
    const denomination = "Mệnh giá:";
    final denominationValue = _selectedDenomination;

    // Footer
    const thankYou = "Cảm ơn quý khách đã sử dụng";

    // Tạo QR code painter
    QrPainter? qrPainter;
    if (_printWithQR) {
      qrPainter = QrPainter(
        data: 'tel:$ussdCode',
        version: QrVersions.auto,
        eyeStyle: const QrEyeStyle(
          eyeShape: QrEyeShape.square,
          color: Colors.black,
        ),
        dataModuleStyle: const QrDataModuleStyle(
          dataModuleShape: QrDataModuleShape.square,
          color: Colors.black,
        ),
      );
    }

    // Vẽ nền trắng cho ảnh
    canvas.drawRect(const Rect.fromLTWH(0, 0, 400, 600),
        paint); // Tăng chiều cao để chứa QR

    // Create text painters
    final storeNamePainter = _createTextPainter(
        storeName, 28, FontWeight.bold, TextAlign.center, 380);
    final storePhonePainter = _createTextPainter(
        storePhone, 23, FontWeight.w600, TextAlign.center, 380);
    final storeAddressPainter = _createTextPainter(
        storeAddress, 23, FontWeight.w500, TextAlign.center, 380);
    final datePrintPainter = _createTextPainter(
        datePrint, 23, FontWeight.normal, TextAlign.left, 180);
    final datePainter = _createTextPainter(
        formattedDate, 23, FontWeight.w600, TextAlign.right, 180);

    // Service information painters
    final serviceNamePainter = _createTextPainter(
        serviceName, 28, FontWeight.normal, TextAlign.left, 180);
    final serviceValuePainter = _createTextPainter(
        serviceValue, 30, FontWeight.bold, TextAlign.right, 180);
    final denominationPainter = _createTextPainter(
        denomination, 28, FontWeight.normal, TextAlign.left, 180);
    final denominationValuePainter = _createTextPainter(
        denominationValue, 30, FontWeight.bold, TextAlign.right, 180);

    final serialLabelPainter = _createTextPainter(
        "Số seri:", 28, FontWeight.normal, TextAlign.left, 180);
    final serialValuePainter = _createTextPainter(
        serialNumber, 28, FontWeight.w800, TextAlign.right, 180);
    final rechargeCodeLabelPainter = _createTextPainter(
        "Mã nạp:", 28, FontWeight.normal, TextAlign.left, 380);
    final rechargeCodeValuePainter = _createTextPainter(
        rechargeCode, 35, FontWeight.bold, TextAlign.right, 380);

    // QR code instruction painter
    final qrInstructionPainter = _createTextPainter(
        "Quét mã QR để nạp thẻ", 20, FontWeight.normal, TextAlign.center, 380);

    // Footer painters
    final thankYouPainter = _createTextPainter(
        thankYou, 20, FontWeight.w500, TextAlign.center, 380);

    // Layout all text elements
    void layoutPainters(List<TextPainter> painters) {
      for (var painter in painters) {
        painter.layout();
      }
    }

    final allPainters = [
      storeNamePainter,
      storePhonePainter,
      storeAddressPainter,
      serviceNamePainter,
      serviceValuePainter,
      denominationPainter,
      denominationValuePainter,
      rechargeCodeLabelPainter,
      rechargeCodeValuePainter,
      serialLabelPainter,
      serialValuePainter,
      datePrintPainter,
      datePainter,
      qrInstructionPainter,
      thankYouPainter
    ];
    layoutPainters(allPainters);

    // Helper function to draw separator line
    void drawSeparatorLine(Canvas canvas, double y) {
      final linePaint = Paint()
        ..color = Colors.black
        ..strokeWidth = 1.0;
      canvas.drawLine(
        Offset(10, y),
        Offset(390, y),
        linePaint,
      );
    }

    //Left aligned
    void drawLeftText(TextPainter painter, double y) {
      painter.paint(canvas, Offset(10, y));
    }

    // Header - Center aligned
    void drawCenteredText(TextPainter painter, double y) {
      painter.paint(canvas, Offset((400 - painter.width) / 2, y));
    }

    // Service information with left-right alignment
    void drawLabelValue(TextPainter label, TextPainter value, double y) {
      label.paint(canvas, Offset(10, y));
      value.paint(canvas, Offset(400 - value.width - 10, y));
    }

    // Draw text elements
    double offsetY = 5;

    // Header
    drawCenteredText(storeNamePainter, offsetY);
    offsetY += storeNamePainter.height + 5;

    drawCenteredText(storePhonePainter, offsetY);
    offsetY += storePhonePainter.height + 5;

    drawCenteredText(storeAddressPainter, offsetY);
    offsetY += storeAddressPainter.height + 5;

    drawLabelValue(datePrintPainter, datePainter, offsetY);
    offsetY += denominationPainter.height + 5;

    // Draw separator line after header
    drawSeparatorLine(canvas, offsetY);
    offsetY += 10;

    drawLabelValue(serviceNamePainter, serviceValuePainter, offsetY);
    offsetY += serviceNamePainter.height + 5;

    drawLabelValue(denominationPainter, denominationValuePainter, offsetY);
    offsetY += denominationPainter.height + 5;

    drawLabelValue(serialLabelPainter, serialValuePainter, offsetY);
    offsetY += serialLabelPainter.height + 5;

    drawCenteredText(rechargeCodeLabelPainter, offsetY);
    offsetY += rechargeCodeLabelPainter.height + 5;

    drawCenteredText(rechargeCodeValuePainter, offsetY);
    offsetY += rechargeCodeValuePainter.height + 15;

    // Vẽ QR code
    if (_printWithQR && qrPainter != null) {
      const qrSize = 70.0;
      final qrOffset = Offset((400 - qrSize) / 2, offsetY);
      canvas.save();
      canvas.translate(qrOffset.dx, qrOffset.dy);
      qrPainter.paint(canvas, const Size(qrSize, qrSize));
      canvas.restore();
      offsetY += qrSize + 10;

      // Draw QR instruction
      drawCenteredText(qrInstructionPainter, offsetY);
      offsetY += qrInstructionPainter.height + 10;
    }
    //End vẽ QR code

    // Draw separator line before footer
    drawSeparatorLine(canvas, offsetY);
    offsetY += 10;

    // Footer
    drawCenteredText(thankYouPainter, offsetY);
    offsetY += thankYouPainter.height + 10;

    final picture = recorder.endRecording();
    final img = await picture.toImage(400, offsetY.toInt());
    final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  }

  TextPainter _createTextPainter(String text, double fontSize, FontWeight fontWeight, TextAlign textAlign, double maxWidth) {
    final textSpan = TextSpan(
      text: text,
      style: TextStyle(
        color: Colors.black,
        fontSize: fontSize,
        fontWeight: fontWeight,
      ),
    );
    return TextPainter(
      text: textSpan,
      textDirection: TextDirection.ltr,
      textAlign: textAlign,
      maxLines: null,
    )..layout(maxWidth: maxWidth);
  }

  Future<void> _showPreview() async {

    if (_textContent.text.isEmpty) {
      showTopSnackBar(context, 'Hãy nhập mã nạp và số serial');
      return;
    }
    final previewImage = await _createImageFromText(_textContent.text);

    setState(() {
      _previewImage = previewImage;
    });

    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext context) {
        // Sử dụng TransformationController để quản lý zoom
        final transformationController = TransformationController();

        return Container(
          height: MediaQuery.of(context).size.height * 0.6,
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(24),
              topRight: Radius.circular(24),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 5),
              const Icon(Icons.expand_less, color: Colors.black, size: 24),
              // Title với icon
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.preview, color: Colors.blue, size: 24),
                    const SizedBox(width: 8),
                    Text(
                      'Xem trước',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: Colors.black,
                          ),
                    ),
                  ],
                ),
              ),

              // Card chứa hình ảnh
              Expanded(
                child: Card(
                  elevation: 5,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  color: Colors.white,
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    child: _previewImage != null
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: InteractiveViewer(
                              transformationController:
                                  transformationController,
                              minScale: 0.5,
                              maxScale: 4.0,
                              child: Image.memory(
                                _previewImage!,
                                fit: BoxFit.contain,
                                width: double.infinity,
                              ),
                            ),
                          )
                        : Center(
                            child: Text(
                              'Không có dữ liệu xem trước',
                              style: Theme.of(context).textTheme.bodyLarge,
                            ),
                          ),
                  ),
                ),
              ),

              // Buttons
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(
                          Icons.close,
                          color: Colors.grey,
                        ),
                        label: const Text(
                          'Đóng',
                          style: TextStyle(color: Colors.grey),
                        ),
                        onPressed: () => Navigator.of(context).pop(),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          side: BorderSide(color: Colors.grey[400]!),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.print),
                        label: const Text('In thẻ'),
                        onPressed: () async {
                          if (_isConnected) {
                            if(!mounted) return;
                            Navigator.of(context).pop();
                            await _printImage();
                          } else {
                            _showBluetoothPopup();
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _printImage() async {
    if (_textContent.text.isEmpty) {
      showTopSnackBar(context, 'Hãy nhập mã nạp và số serial');
      return;
    }

    try {
      final imageData = await _createImageFromText(_textContent.text);

      Map<String, dynamic> config = {};
      List<LineText> list = [];

      list.add(LineText(
        type: LineText.TYPE_IMAGE,
        content: base64Encode(imageData),
        width: 380,
        height: 380,
      ));

      await bluetoothPrint.printReceipt(config, list);

      if (!mounted) return;
      showTopSnackBar(context, 'In thành công!');
      resetFields(); // Làm mới sau khi in
    } catch (e) {
      showTopSnackBar(context, 'Lỗi khi in !');
      if (kDebugMode) {
        print("Lỗi khi in: $e");
      }
    }
  }

  void resetFields() {
    setState(() {
      _textContent.clear();
    });
  }

  Widget _buildConnectedDeviceSection() {
    final connectedDevice = ConnectedDeviceManager.getConnectedDevice();
    if (connectedDevice == null || !_isConnected) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.green.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.green.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.green.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.print,
              color: Colors.green,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Thiết bị đã kết nối',
                  style: TextStyle(
                    fontWeight: FontWeight.w500,
                    color: Colors.green,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  connectedDevice.name ?? 'Không xác định',
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
                Text(
                  connectedDevice.address ?? '',
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton(StateSetter setDialogState) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        icon: Icon(_isConnected ? Icons.bluetooth_disabled : Icons.bluetooth),
        label: Text(_isConnected ? 'Ngắt kết nối' : 'Kết nối'),
        onPressed: _isSearching
            ? null
            : () async {
                setDialogState(() {
                  if (_isConnected) {
                    _disconnectBluetooth();
                  } else {
                    _connectBluetooth();
                  }
                });
              },
        style: ElevatedButton.styleFrom(
          backgroundColor: _isConnected ? Colors.red : Colors.blue,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Row(
      children: [
        const Icon(Icons.bluetooth, color: Colors.blue, size: 24),
        const SizedBox(width: 12),
        const Expanded(
          child: Text(
            'Kết nối máy in',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.close),
          color: Colors.red,
          onPressed:_isSearching
              ? null
              : () => Navigator.pop(context),
          style: IconButton.styleFrom(
            backgroundColor: Colors.grey.shade100,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStatusBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: _isConnected ? Colors.green.shade50 : Colors.blue.shade50,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(
            _isConnected ? Icons.check_circle : Icons.info_outline,
            color: _isConnected ? Colors.green : Colors.blue,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _isConnected ? 'Đã kết nối' : 'Chưa kết nối',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  _deviceMsg,
                  style: TextStyle(
                    color: Colors.grey.shade700,
                    fontSize: 12,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDevicesList(StateSetter setDialogState) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade200),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          // Header với nút refresh và loading indicator
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(8)),
            ),
            child: Row(
              children: [
                Text(
                  'Danh sách thiết bị',
                  style: TextStyle(
                    fontWeight: FontWeight.w500,
                    color: Colors.grey.shade700,
                  ),
                ),
                const Spacer(),
                if (_isSearching)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: _isSearching
                      ? null
                      : () async {
                          setDialogState(() => _isSearching = true);
                          await _searchDevices();
                        },
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          // List thiết bị
          Expanded(
            child: _devices.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        _isSearching
                            ? 'Đang tìm...'
                            : 'Không có thiết bị',
                        style: TextStyle(color: Colors.grey.shade600),
                      ),
                    ),
                  )
                : ListView.separated(
                    itemCount: _devices.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final device = _devices[index];
                      final isSelected = _selectedDevice == device;
                      final isConnected = _isConnected &&
                          ConnectedDeviceManager.getConnectedDevice() == device;

                      return ListTile(
                        dense: true,
                        selected: isSelected,
                        selectedTileColor: Colors.blue.shade50,
                        leading: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: isConnected
                                ? Colors.green.shade100
                                : isSelected
                                    ? Colors.blue.shade100
                                    : Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            Icons.print,
                            color: isConnected
                                ? Colors.green
                                : isSelected
                                    ? Colors.blue
                                    : Colors.grey,
                            size: 20,
                          ),
                        ),
                        title: Text(
                          device.name ?? 'Không xác định',
                          style: TextStyle(
                            fontWeight: FontWeight.w500,
                            color: isConnected ? Colors.green : null,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          device.address ?? '...',
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 12,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: isConnected
                            ? const Icon(Icons.check_circle,
                                color: Colors.green)
                            : isSelected
                                ? const Icon(Icons.check_circle,
                                    color: Colors.blue)
                                : null,
                        onTap: () {
                          setDialogState(() {
                            _selectedDevice = device;
                            _deviceMsg = 'Đã chọn: ${device.name}';
                          });
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  void _showBluetoothPopup() {
    showDialog(
      context: context,
      barrierDismissible: false, // Ngăn đóng popup khi click bên ngoài
      builder: (BuildContext context) {
        // // Tự động tìm kiếm thiết bị nếu chưa có
        if (_devices.isEmpty) {
          Future.delayed(Duration.zero, () => _searchDevices());
        }
        return Dialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: StatefulBuilder(
            builder: (BuildContext context, StateSetter setDialogState) {
              _listenToBluetoothState(setDialogState);
              return ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: 400,
                  maxHeight: MediaQuery.of(context).size.height * 0.7,
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildHeader(context),
                      const SizedBox(height: 16),
                      _buildStatusBar(),
                      const SizedBox(height: 16),
                      //if (_isConnected) _buildConnectedDeviceSection(),
                      Expanded(
                        child: _buildDevicesList(setDialogState),
                      ),
                      const SizedBox(height: 16),
                      _buildActionButton(setDialogState),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  Future<bool> _onWillPop() async {
    if (_showExitWarning) {
      await _disconnectBluetooth();
      return true;
    }

    if (_textContent.text.isNotEmpty) {
      setState(() {
        _textContent.clear();
        showTopSnackBar(context, 'Đã xóa mã thẻ');
      });
      return false;
    }

    final now = DateTime.now();
    if (_lastBackPress == null ||
        now.difference(_lastBackPress!) > const Duration(seconds: 2)) {
      _lastBackPress = now;
      setState(() {
        _showExitWarning = true;
      });

      showTopSnackBar(context, 'Nhấn trở về lần nữa để thoát');

      _exitWarningTimer?.cancel();
      _exitWarningTimer = Timer(const Duration(seconds: 2), () {
        if (mounted) {
          setState(() {
            _showExitWarning = false;
          });
        }
      });
      return false;
    }

    await _disconnectBluetooth();
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: _onWillPop,
      child: MediaQuery(
        data: MediaQuery.of(context).copyWith(
            textScaler: MediaQuery.textScalerOf(context)
                .clamp(minScaleFactor: 1.0, maxScaleFactor: 1.2)),
        child: Scaffold(
          appBar: AppBar(
            backgroundColor: Colors.white,
            elevation: 0,
            title: const FittedBox(
              fit: BoxFit.scaleDown,
              child: Icon(Icons.print, size: 40, color: Colors.black,),
            ),
            centerTitle: true,
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(1.0),
              child: Container(
                color: Colors.grey[300],
                height: 1.0,
              ),
            ),
          ),
          backgroundColor: Colors.grey[300],
          // Wrap body with ResizeToAvoidBottomInset
          resizeToAvoidBottomInset: true,
          body: GestureDetector(
            onTap: () {
              FocusScope.of(context).unfocus();
            },
            child: SafeArea(
              child: SingleChildScrollView(
                child: Padding(
                  padding: EdgeInsets.only(
                    left: 16.0,
                    right: 16.0,
                    top: 16.0,
                    // Add padding to bottom to ensure content is visible above keyboard
                    bottom: MediaQuery.of(context).viewInsets.bottom + 16.0,
                  ),
                  child: Column(
                    children: [
                      // Card kết nối máy in
                      Card(
                        elevation: 2,
                        color: Colors.white,
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.bluetooth,
                                      color: Colors.blue),
                                  const SizedBox(width: 8),
                                  const Text(
                                    'Kết nối máy in',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const Spacer(),
                                  IconButton(
                                    icon: const Icon(Icons.settings),
                                    onPressed: _showBluetoothPopup,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  Text(
                                    'Trạng thái: ',
                                    style: TextStyle(
                                      color: Colors.grey[600],
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  //const Spacer(),
                                  Text(
                                    _isConnected ? 'Sẵn sàng' : 'Chưa kết nối',
                                    style: TextStyle(
                                      color: _isConnected
                                          ? Colors.green
                                          : Colors.red,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const Spacer(),
                                  Text(
                                    _isConnected
                                        ? '${_selectedDevice?.name}'
                                        : '',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w500,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                              //const SizedBox(height: 8),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Card nhập thông tin thẻ
                      Card(
                        elevation: 2,
                        color: Colors.white,
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                crossAxisAlignment:
                                CrossAxisAlignment.center,
                                children: [
                                  Expanded(
                                      child: Column(
                                    children: [
                                      RoundedCheckbox(
                                        value: _printWithQR,
                                        onChanged: (value) {
                                          setState(() {
                                            _printWithQR = value;
                                          });
                                        },
                                        title: 'In kèm mã QR',
                                        icon: Icons.qr_code,
                                      ),
                                      const SizedBox(height: 20),
                                    ],
                                  ))
                                ],
                              ),
                              Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          'Nhà mạng',
                                          style: TextStyle(
                                            color: Colors.grey,
                                            fontSize: 14,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 4),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 10),
                                          decoration: BoxDecoration(
                                            border: Border.all(
                                                color: Colors.grey.shade300),
                                            borderRadius:
                                                BorderRadius.circular(8),
                                          ),
                                          child: DropdownButton<String>(
                                            value: _selectedProvider,
                                            isExpanded: true,
                                            underline: Container(),
                                            items: _providerDenominations.keys
                                                .map((String provider) {
                                              return DropdownMenuItem<String>(
                                                value: provider,
                                                child: Text(
                                                  provider,
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              );
                                            }).toList(),
                                            onChanged: (newValue) {
                                              setState(() {
                                                _selectedProvider = newValue!;
                                                _selectedDenomination =
                                                    _providerDenominations[
                                                        _selectedProvider]![0];
                                              });
                                            },
                                            dropdownColor: Colors.white,
                                            borderRadius:
                                                const BorderRadius.all(
                                                    Radius.circular(10)),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          'Mệnh giá',
                                          style: TextStyle(
                                            color: Colors.grey,
                                            fontSize: 14,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 4),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 12),
                                          decoration: BoxDecoration(
                                            border: Border.all(
                                                color: Colors.grey.shade300),
                                            borderRadius:
                                                BorderRadius.circular(8),
                                          ),
                                          child: DropdownButton<String>(
                                            value: _selectedDenomination,
                                            isExpanded: true,
                                            underline: Container(),
                                            items: _providerDenominations[
                                                    _selectedProvider]!
                                                .map((String denomination) {
                                              return DropdownMenuItem<String>(
                                                value: denomination,
                                                child: Text(
                                                  denomination,
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                              );
                                            }).toList(),
                                            onChanged: (newValue) {
                                              setState(() {
                                                _selectedDenomination =
                                                    newValue!;
                                              });
                                            },
                                            dropdownColor: Colors.white,
                                            borderRadius:
                                                const BorderRadius.all(
                                                    Radius.circular(10)),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 20),
                              const Text(
                                'Mã thẻ',
                                style: TextStyle(
                                  color: Colors.grey,
                                  fontSize: 14,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              TextField(
                                focusNode: _focusNode,
                                controller: _textContent,
                                decoration: InputDecoration(
                                  hintText: 'Nhập mã nạp và số serial',
                                  hintStyle: TextStyle(color: Colors.grey[400]),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide:
                                        BorderSide(color: Colors.grey.shade300),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide:
                                        BorderSide(color: Colors.grey.shade300),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide:
                                        const BorderSide(color: Colors.blue),
                                  ),
                                ),
                                minLines: 1,
                                maxLines: 5,
                              ),
                              const SizedBox(height: 16),
                              Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      icon: const Icon(
                                        Icons.visibility,
                                        color: Colors.green,
                                      ),
                                      label: const Text(
                                        'Xem',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(color: Colors.green),
                                      ),
                                      onPressed: _showPreview,
                                      style: OutlinedButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 12),
                                        shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(8),
                                        ),
                                        side: const BorderSide(
                                          color: Colors.green,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: ElevatedButton.icon(
                                      icon: const Icon(Icons.print),
                                      label: const Text('In thẻ'),
                                      onPressed: _printImage,
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.blue,
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 12),
                                        shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(8),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
