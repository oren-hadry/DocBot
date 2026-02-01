import "dart:convert";
import "dart:io";
import "dart:typed_data";

import "package:flutter/foundation.dart";
import "package:flutter/material.dart";
import "package:flutter_localizations/flutter_localizations.dart";
import "package:image_picker/image_picker.dart";
import "package:http/http.dart" as http;
import "package:path_provider/path_provider.dart";
import "package:open_filex/open_filex.dart";
import "package:share_plus/share_plus.dart";
import "package:speech_to_text/speech_to_text.dart" as stt;
import "package:shared_preferences/shared_preferences.dart";
import "package:permission_handler/permission_handler.dart";
import "package:flutter_contacts/flutter_contacts.dart";
import "package:url_launcher/url_launcher.dart";
import "package:photo_manager/photo_manager.dart";
import "package:in_app_update/in_app_update.dart";
import "package:package_info_plus/package_info_plus.dart";
import "package:flutter/services.dart";
import "package:flutter_secure_storage/flutter_secure_storage.dart";
import "package:crypto/crypto.dart";
import "l10n/strings.dart";
import "local/history_store.dart";

const String _apiBaseUrlEnv = String.fromEnvironment("API_BASE_URL", defaultValue: "");
const bool _allowInsecureHttp = bool.fromEnvironment("ALLOW_INSECURE_HTTP", defaultValue: false);
const String _pinnedCertSha256 = String.fromEnvironment("PINNED_CERT_SHA256", defaultValue: "");
const String _iosBundleId = "com.example.docbot_app";
const String _iosAppStoreId = "";

String resolveApiBaseUrl() {
  if (_apiBaseUrlEnv.isNotEmpty) {
    return _apiBaseUrlEnv;
  }
  if (kIsWeb) {
    return "http://localhost:8000";
  }
  if (Platform.isAndroid) {
    return "http://10.0.2.2:8000";
  }
  if (Platform.isIOS) {
    return "http://localhost:8000";
  }
  return "http://localhost:8000";
}

final String apiBaseUrl = resolveApiBaseUrl();
final ValueNotifier<Locale> appLocale = ValueNotifier(const Locale("he", "IL"));
final ValueNotifier<bool> isLoggedIn = ValueNotifier(false);
final ValueNotifier<String?> currentUserKey = ValueNotifier(null);
const _secureStorage = FlutterSecureStorage();

String _bytesToHex(Uint8List bytes) {
  final buffer = StringBuffer();
  for (final b in bytes) {
    buffer.write(b.toRadixString(16).padLeft(2, "0"));
  }
  return buffer.toString();
}

class PinnedHttpOverrides extends HttpOverrides {
  PinnedHttpOverrides(this.pinnedSha256);

  final String pinnedSha256;

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);
    if (pinnedSha256.isEmpty) return client;
    client.badCertificateCallback = (cert, host, port) {
      try {
        final hash = sha256.convert(cert.der).bytes;
        final hex = _bytesToHex(Uint8List.fromList(hash));
        return hex == pinnedSha256.toLowerCase();
      } catch (_) {
        return false;
      }
    };
    return client;
  }
}

Future<String?> _readAuthToken() async {
  if (kIsWeb) {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString("auth_token");
  }
  return _secureStorage.read(key: "auth_token");
}

Future<void> _writeAuthToken(String token) async {
  if (kIsWeb) {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString("auth_token", token);
    return;
  }
  await _secureStorage.write(key: "auth_token", value: token);
}

Future<void> _deleteAuthToken() async {
  if (kIsWeb) {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove("auth_token");
    return;
  }
  await _secureStorage.delete(key: "auth_token");
}

void toggleLocale() {
  final current = appLocale.value.languageCode;
  appLocale.value = current == "he" ? const Locale("en", "US") : const Locale("he", "IL");
}

Future<void> clearUserFiles(BuildContext context) async {
  if (kIsWeb) return;
  final proceed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(t(context, "clean_files_title")),
      content: Text(t(context, "clean_files_body")),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(t(context, "cancel_button")),
        ),
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(t(context, "clean_files_button")),
        ),
      ],
    ),
  );
  if (proceed != true) return;

  try {
    final dir = await getApplicationDocumentsDirectory();
    // 1. Clear photo backups
    final backupDir = Directory("${dir.path}/photo_backups");
    if (await backupDir.exists()) {
      await backupDir.delete(recursive: true);
      await backupDir.create();
    }
    // 2. Clear temp media in app_flutter
    final list = dir.listSync();
    for (final item in list) {
      if (item is File) {
        final name = item.uri.pathSegments.last;
        if (name.startsWith("res_timestamp")) {
          await item.delete();
        }
      }
    }
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t(context, "clean_files_success"))),
      );
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error: $e")),
      );
    }
  }
}

List<Widget> appBarActions(
  BuildContext context, {
  bool showLogout = false,
  bool showCancelReport = false,
  List<PopupMenuEntry<String>>? extraItems,
  void Function(String)? onSelected,
}) {
  return [
    PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert),
      onSelected: (value) {
        if (value == "language") {
          toggleLocale();
        } else if (value == "cancel_report") {
          onSelected?.call(value);
        } else if (value == "logout") {
          logout(context);
        } else if (value == "clean_files") {
          clearUserFiles(context);
        } else if (value == "exit_app") {
          SystemNavigator.pop();
        } else {
          onSelected?.call(value);
        }
      },
      itemBuilder: (context) {
        final items = <PopupMenuEntry<String>>[
          if (extraItems != null) ...extraItems,
          if (showCancelReport)
            PopupMenuItem<String>(
              value: "cancel_report",
              child: Text(t(context, "cancel_report_button")),
            ),
          PopupMenuItem<String>(
            value: "language",
            child: Text(t(context, "toggle_language")),
          ),
          PopupMenuItem<String>(
            value: "clean_files",
            child: Text(t(context, "clean_files_button")),
          ),
        ];
        if (showLogout) {
          items.add(
            PopupMenuItem<String>(
              value: "logout",
              child: Text(t(context, "logout_button")),
            ),
          );
        }
        items.add(
          PopupMenuItem<String>(
            value: "exit_app",
            child: Text(t(context, "exit_app_button")),
          ),
        );
        return items;
      },
    ),
  ];
}

TextDirection _textDirection(BuildContext context) {
  return Localizations.localeOf(context).languageCode == "he"
      ? TextDirection.rtl
      : TextDirection.ltr;
}

TextAlign _textAlign(BuildContext context) {
  return Localizations.localeOf(context).languageCode == "he"
      ? TextAlign.right
      : TextAlign.left;
}

String _safeFilePart(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return "";
  final sanitized = trimmed.replaceAll(RegExp(r'[\\/:*?"<>|]+'), "_");
  return sanitized.replaceAll(RegExp(r"\s+"), "_");
}

String _deriveUserKey(Map<String, dynamic> profile) {
  final email = (profile["email"] ?? "").toString().trim().toLowerCase();
  if (email.isNotEmpty) {
    return "email:$email";
  }
  final userId = (profile["user_id"] ?? "").toString().trim();
  return "user:$userId";
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kIsWeb && _pinnedCertSha256.isNotEmpty) {
    HttpOverrides.global = PinnedHttpOverrides(_pinnedCertSha256);
  }
  if (!kIsWeb && kReleaseMode && apiBaseUrl.startsWith("http://") && !_allowInsecureHttp) {
    throw StateError("Insecure HTTP is blocked in release builds.");
  }
  final token = await _readAuthToken();
  if (token != null && token.isNotEmpty) {
    api.token = token;
    isLoggedIn.value = true;
    final prefs = await SharedPreferences.getInstance();
    final storedKey = prefs.getString("current_user_key");
    if (storedKey != null && storedKey.isNotEmpty) {
      currentUserKey.value = storedKey;
    } else {
      try {
        final profile = await api.getCurrentUser();
        final key = _deriveUserKey(profile);
        currentUserKey.value = key;
        await prefs.setString("current_user_key", key);
      } catch (_) {}
    }
    await _cleanupLegacyHistory();
  }
  runApp(const DocBotApp());
}

Future<void> _cleanupLegacyHistory() async {
  const legacyKeys = [
    "history_locations",
    "history_contact_names",
    "history_contact_emails",
    "history_descriptions",
    "history_notes",
  ];
  final removed = await HistoryStore.clearLegacyHistory(legacyKeys);
  if (removed.isNotEmpty) {
    debugPrint("Cleared legacy history keys: ${removed.join(", ")}");
  }
}

class DocBotApp extends StatelessWidget {
  const DocBotApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Locale>(
      valueListenable: appLocale,
      builder: (context, locale, _) {
        final isRtl = locale.languageCode == "he";
        return MaterialApp(
          title: "DocBotApp",
          theme: ThemeData(useMaterial3: true),
          locale: locale,
          supportedLocales: const [Locale("he", "IL"), Locale("en", "US")],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          builder: (context, child) => UpdateChecker(
            child: Directionality(
              textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
              child: child ?? const SizedBox.shrink(),
            ),
          ),
          home: ValueListenableBuilder<bool>(
            valueListenable: isLoggedIn,
            builder: (context, loggedIn, _) {
              return loggedIn ? const StartReportScreen() : const LoginScreen();
            },
          ),
        );
      },
    );
  }
}

class UpdateChecker extends StatefulWidget {
  const UpdateChecker({super.key, required this.child});

  final Widget child;

  @override
  State<UpdateChecker> createState() => _UpdateCheckerState();
}

class _UpdateCheckerState extends State<UpdateChecker> {
  bool _checked = false;

  @override
  void initState() {
    super.initState();
    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _checkForUpdate());
    }
  }

  Future<void> _checkForUpdate() async {
    if (_checked) return;
    _checked = true;
    try {
      if (Platform.isAndroid) {
        final info = await InAppUpdate.checkForUpdate();
        if (info.updateAvailability == UpdateAvailability.updateAvailable) {
          if (info.immediateUpdateAllowed) {
            await InAppUpdate.performImmediateUpdate();
          } else if (info.flexibleUpdateAllowed) {
            await InAppUpdate.startFlexibleUpdate();
            await InAppUpdate.completeFlexibleUpdate();
          }
        }
      } else if (Platform.isIOS) {
        await _checkIosUpdate();
      }
    } catch (_) {}
  }

  Future<void> _checkIosUpdate() async {
    if (_iosBundleId.isEmpty || !mounted) return;
    try {
      final info = await PackageInfo.fromPlatform();
      final resp = await http.get(
        Uri.parse("https://itunes.apple.com/lookup?bundleId=$_iosBundleId"),
      );
      if (resp.statusCode != 200) return;
      final data = jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
      final results = (data["results"] as List?) ?? [];
      if (results.isEmpty) return;
      final storeVersion = results.first["version"]?.toString() ?? "";
      final storeUrl =
          results.first["trackViewUrl"]?.toString() ?? (_iosAppStoreId.isNotEmpty
              ? "https://apps.apple.com/app/id$_iosAppStoreId"
              : "");
      if (storeVersion.isEmpty || storeUrl.isEmpty) return;
      if (_isNewerVersion(storeVersion, info.version)) {
        await _showIosUpdateDialog(storeUrl);
      }
    } catch (_) {}
  }

  bool _isNewerVersion(String store, String current) {
    List<int> parse(String v) => v.split(".").map((e) => int.tryParse(e) ?? 0).toList();
    final a = parse(store);
    final b = parse(current);
    final len = a.length > b.length ? a.length : b.length;
    for (int i = 0; i < len; i++) {
      final ai = i < a.length ? a[i] : 0;
      final bi = i < b.length ? b[i] : 0;
      if (ai > bi) return true;
      if (ai < bi) return false;
    }
    return false;
  }

  Future<void> _showIosUpdateDialog(String storeUrl) async {
    if (!mounted) return;
    final proceed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t(context, "update_available_title")),
        content: Text(t(context, "update_available_body")),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(t(context, "later_button")),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(t(context, "update_button")),
          ),
        ],
      ),
    );
    if (proceed == true) {
      final uri = Uri.parse(storeUrl);
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class TemplateInfo {
  TemplateInfo({required this.key, required this.title, required this.titleHe});

  final String key;
  final String title;
  final String titleHe;

  factory TemplateInfo.fromJson(Map<String, dynamic> json) {
    return TemplateInfo(
      key: json["key"],
      title: json["title"],
      titleHe: json["title_he"] ?? json["title"],
    );
  }
}

class ContactInfo {
  ContactInfo({
    required this.id,
    required this.name,
    required this.email,
    this.company,
    this.roleTitle,
    this.phone,
  });

  final String id;
  final String name;
  final String email;
  final String? company;
  final String? roleTitle;
  final String? phone;

  factory ContactInfo.fromJson(Map<String, dynamic> json) {
    return ContactInfo(
      id: json["id"],
      name: json["name"],
      email: json["email"],
      company: json["company"],
      roleTitle: json["role_title"],
      phone: json["phone"],
    );
  }
}

class ReportSummary {
  ReportSummary({
    required this.reportId,
    required this.createdAt,
    required this.location,
    required this.templateKey,
    required this.title,
    required this.titleHe,
    required this.folder,
    required this.tags,
  });

  final String reportId;
  final String createdAt;
  final String location;
  final String templateKey;
  final String title;
  final String titleHe;
  final String folder;
  final List<String> tags;

  factory ReportSummary.fromJson(Map<String, dynamic> json) {
    return ReportSummary(
      reportId: json["report_id"],
      createdAt: json["created_at"],
      location: json["location"] ?? "",
      templateKey: json["template_key"] ?? "",
      title: json["title"] ?? "",
      titleHe: json["title_he"] ?? json["title"] ?? "",
      folder: json["folder"] ?? "",
      tags: (json["tags"] as List?)?.map((e) => e.toString()).toList() ?? [],
    );
  }
}

class ReportItemData {
  ReportItemData({
    required this.id,
    required this.number,
    required this.description,
    required this.notes,
  });

  final String id;
  final String number;
  final String description;
  final String notes;

  factory ReportItemData.fromJson(Map<String, dynamic> json) {
    return ReportItemData(
      id: json["id"],
      number: json["number"],
      description: json["description"] ?? "",
      notes: json["notes"] ?? "",
    );
  }
}

class ReportPhotoData {
  ReportPhotoData({required this.id, required this.itemId});

  final String id;
  final String? itemId;

  factory ReportPhotoData.fromJson(Map<String, dynamic> json) {
    return ReportPhotoData(
      id: json["id"],
      itemId: json["item_id"],
    );
  }
}

class ActiveSessionData {
  ActiveSessionData({
    required this.items,
    required this.photos,
    required this.location,
    required this.title,
    required this.titleHe,
    required this.templateKey,
    required this.attendees,
    required this.distributionList,
  });

  final List<ReportItemData> items;
  final List<ReportPhotoData> photos;
  final String location;
  final String title;
  final String titleHe;
  final String templateKey;
  final List<String> attendees;
  final List<String> distributionList;
}

class ApiClient {
  String? token;

  Future<Map<String, dynamic>> getCurrentUser() async {
    final resp = await http.get(
      Uri.parse("$apiBaseUrl/auth/me"),
      headers: _headers(),
    );
    if (resp.statusCode != 200) {
      throw Exception(resp.body);
    }
    return _decodeJson(resp) as Map<String, dynamic>;
  }

  dynamic _decodeJson(http.Response resp) {
    return jsonDecode(utf8.decode(resp.bodyBytes));
  }

  Future<String> login(String phone, String password) async {
    final resp = await http.post(
      Uri.parse("$apiBaseUrl/auth/login"),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({"phone": phone, "password": password}),
    );
    if (resp.statusCode != 200) {
      throw Exception(resp.body);
    }
    return (_decodeJson(resp) as Map<String, dynamic>)["access_token"] as String;
  }

  Future<String> register(String phone, String password) async {
    final resp = await http.post(
      Uri.parse("$apiBaseUrl/auth/register"),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({"phone": phone, "password": password}),
    );
    if (resp.statusCode != 200) {
      throw Exception(resp.body);
    }
    return (_decodeJson(resp) as Map<String, dynamic>)["access_token"] as String;
  }

  Future<void> requestEmailCode(String phone, String email, String password) async {
    final resp = await http.post(
      Uri.parse("$apiBaseUrl/auth/request_email_code"),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({"phone": phone, "email": email, "password": password}),
    );
    if (resp.statusCode != 200) {
      throw Exception(resp.body);
    }
  }

  Future<String> verifyEmailCode(String phone, String code) async {
    final resp = await http.post(
      Uri.parse("$apiBaseUrl/auth/verify_email"),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({"phone": phone, "code": code}),
    );
    if (resp.statusCode != 200) {
      throw Exception(resp.body);
    }
    return (_decodeJson(resp) as Map<String, dynamic>)["access_token"] as String;
  }

  Future<List<String>> listLocations() async {
    final resp = await http.get(
      Uri.parse("$apiBaseUrl/reports/locations"),
      headers: _headers(),
    );
    if (resp.statusCode != 200) {
      throw Exception(resp.body);
    }
    final data = _decodeJson(resp) as Map<String, dynamic>;
    return (data["locations"] as List).map((e) => e.toString()).toList();
  }

  Future<List<ReportSummary>> listRecentReports() async {
    final resp = await http.get(
      Uri.parse("$apiBaseUrl/reports/recent"),
      headers: _headers(),
    );
    if (resp.statusCode != 200) {
      throw Exception(resp.body);
    }
    final data = _decodeJson(resp) as Map<String, dynamic>;
    final items = (data["reports"] as List).cast<Map<String, dynamic>>();
    return items.map(ReportSummary.fromJson).toList();
  }

  Future<void> openReport(String reportId) async {
    final resp = await http.post(
      Uri.parse("$apiBaseUrl/reports/$reportId/open"),
      headers: _headers(),
    );
    if (resp.statusCode != 200) {
      throw Exception(resp.body);
    }
  }

  Future<ActiveSessionData> getActiveSession() async {
    final resp = await http.get(
      Uri.parse("$apiBaseUrl/reports/session"),
      headers: _headers(),
    );
    if (resp.statusCode != 200) {
      throw Exception(resp.body);
    }
    final data = _decodeJson(resp) as Map<String, dynamic>;
    final session = data["session"] as Map<String, dynamic>;
    final items = (session["items"] as List).cast<Map<String, dynamic>>();
    final photos = (session["photos"] as List? ?? []).cast<Map<String, dynamic>>();
    return ActiveSessionData(
      items: items.map(ReportItemData.fromJson).toList(),
      photos: photos.map(ReportPhotoData.fromJson).toList(),
      location: session["location"]?.toString() ?? "",
      title: session["title"]?.toString() ?? "",
      titleHe: session["title_he"]?.toString() ?? session["title"]?.toString() ?? "",
      templateKey: session["template_key"]?.toString() ?? "",
      attendees: (session["attendees"] as List? ?? []).map((e) => e.toString()).toList(),
      distributionList:
          (session["distribution_list"] as List? ?? []).map((e) => e.toString()).toList(),
    );
  }

  Future<void> updateItem(String itemId, String description, String notes) async {
    final resp = await http.put(
      Uri.parse("$apiBaseUrl/reports/item/$itemId"),
      headers: _headers(),
      body: jsonEncode({"description": description, "notes": notes}),
    );
    if (resp.statusCode != 200) {
      throw Exception(resp.body);
    }
  }

  Future<void> organizeReport(String reportId, String folder, List<String> tags) async {
    final resp = await http.post(
      Uri.parse("$apiBaseUrl/reports/$reportId/organize"),
      headers: _headers(),
      body: jsonEncode({"folder": folder, "tags": tags}),
    );
    if (resp.statusCode != 200) {
      throw Exception(resp.body);
    }
  }

  Future<void> startReport(String location, String templateKey) async {
    final resp = await http.post(
      Uri.parse("$apiBaseUrl/reports/start"),
      headers: _headers(),
      body: jsonEncode({"location": location, "template_key": templateKey}),
    );
    if (resp.statusCode != 200) {
      throw Exception(resp.body);
    }
  }

  Future<String> addItem(String description, String notes, {bool allowEmpty = false}) async {
    final resp = await http.post(
      Uri.parse("$apiBaseUrl/reports/item"),
      headers: _headers(),
      body: jsonEncode({"description": description, "notes": notes, "allow_empty": allowEmpty}),
    );
    if (resp.statusCode != 200) {
      throw Exception(resp.body);
    }
    return (_decodeJson(resp) as Map<String, dynamic>)["item_id"] as String;
  }

  Future<void> uploadPhoto(File file, {String? itemId}) async {
    final req = http.MultipartRequest("POST", Uri.parse("$apiBaseUrl/reports/photo"));
    if (token != null) {
      req.headers["Authorization"] = "Bearer $token";
    }
    if (itemId != null) {
      req.fields["item_id"] = itemId;
    }
    req.files.add(await http.MultipartFile.fromPath("file", file.path));
    final resp = await req.send();
    if (resp.statusCode != 200) {
      throw Exception(await resp.stream.bytesToString());
    }
  }

  Future<List<TemplateInfo>> listTemplates() async {
    final resp = await http.get(
      Uri.parse("$apiBaseUrl/reports/templates"),
      headers: _headers(),
    );
    if (resp.statusCode != 200) {
      throw Exception(resp.body);
    }
    final data = _decodeJson(resp) as Map<String, dynamic>;
    final items = (data["templates"] as List).cast<Map<String, dynamic>>();
    return items.map(TemplateInfo.fromJson).toList();
  }

  Future<List<ContactInfo>> listContacts() async {
    final resp = await http.get(
      Uri.parse("$apiBaseUrl/contacts"),
      headers: _headers(),
    );
    if (resp.statusCode != 200) {
      throw Exception(resp.body);
    }
    final data = _decodeJson(resp) as Map<String, dynamic>;
    final items = (data["contacts"] as List).cast<Map<String, dynamic>>();
    return items.map(ContactInfo.fromJson).toList();
  }

  Future<ContactInfo> addContact({
    required String name,
    required String email,
    String? company,
    String? roleTitle,
    String? phone,
  }) async {
    final resp = await http.post(
      Uri.parse("$apiBaseUrl/contacts"),
      headers: _headers(),
      body: jsonEncode({
        "name": name,
        "email": email,
        "company": company,
        "role_title": roleTitle,
        "phone": phone,
      }),
    );
    if (resp.statusCode != 200) {
      throw Exception(resp.body);
    }
    final data = _decodeJson(resp) as Map<String, dynamic>;
    return ContactInfo.fromJson(data["contact"]);
  }

  Future<void> setReportContacts({
    required List<String> attendees,
    required List<String> distributionList,
  }) async {
    final resp = await http.post(
      Uri.parse("$apiBaseUrl/reports/contacts"),
      headers: _headers(),
      body: jsonEncode({
        "attendees": attendees,
        "distribution_list": distributionList,
      }),
    );
    if (resp.statusCode != 200) {
      throw Exception(resp.body);
    }
  }

  Future<String> finalizeAndSave({String? filename}) async {
    final resp = await http.post(
      Uri.parse("$apiBaseUrl/reports/finalize"),
      headers: _headers(json: false),
    );
    if (resp.statusCode != 200) {
      throw Exception(resp.body);
    }
    final dir = await getApplicationDocumentsDirectory();
    final fallback = "Report_${DateTime.now().millisecondsSinceEpoch}.docx";
    final name = (filename == null || filename.isEmpty) ? fallback : filename;
    final finalName = name.endsWith(".docx") ? name : "$name.docx";
    final file = File("${dir.path}/$finalName");
    await file.writeAsBytes(resp.bodyBytes);
    return file.path;
  }

  Future<void> cancelReport() async {
    final resp = await http.post(
      Uri.parse("$apiBaseUrl/reports/cancel"),
      headers: _headers(),
    );
    if (resp.statusCode != 200) {
      throw Exception(resp.body);
    }
  }

  Future<void> sendDebugLog(String event, Map<String, dynamic> data) async {
    try {
      await http.post(
        Uri.parse("$apiBaseUrl/debug/log"),
        headers: _headers(),
        body: jsonEncode({"event": event, "data": data}),
      );
    } catch (_) {}
  }

  Map<String, String> _headers({bool json = true}) {
    final headers = <String, String>{};
    if (token != null) {
      headers["Authorization"] = "Bearer $token";
    }
    if (json) {
      headers["Content-Type"] = "application/json";
    }
    return headers;
  }
}

final api = ApiClient();

Future<void> logout(BuildContext context) async {
  final prefs = await SharedPreferences.getInstance();
  await _deleteAuthToken();
  await prefs.remove("current_user_key");
  api.token = null;
  currentUserKey.value = null;
  isLoggedIn.value = false;
  if (context.mounted) {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final phoneController = TextEditingController();
  final passwordController = TextEditingController();
  final emailController = TextEditingController();
  String? error;
  String? connectionStatus;
  bool loading = false;
  bool emailEditable = false;

  @override
  void initState() {
    super.initState();
    _loadSavedEmail();
  }

  Future<void> _loadSavedEmail() async {
    final prefs = await SharedPreferences.getInstance();
    final savedEmail = prefs.getString("saved_email") ?? "";
    if (savedEmail.isNotEmpty) {
      emailController.text = savedEmail;
      setState(() => emailEditable = false);
    } else {
      setState(() => emailEditable = true);
    }
  }

  Future<void> _auth() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final phone = phoneController.text.trim();
      final password = passwordController.text;
      try {
        final token = await api.login(phone, password);
        await _saveToken(token);
        if (mounted) {
          Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const StartReportScreen()));
        }
        return;
      } catch (_) {
        setState(() => emailEditable = true);
        final email = emailController.text.trim();
        if (email.isEmpty) {
          setState(() => error = t(context, "error_email_required"));
          return;
        }
        final accepted = await _showTermsAndAccept();
        if (!accepted) {
          setState(() => error = t(context, "email_verification_failed"));
          return;
        }
        await api.requestEmailCode(phone, email, password);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(t(context, "email_verification_sent"))),
          );
        }
        final code = await _promptForCode();
        if (code == null || code.isEmpty) {
          setState(() => error = t(context, "email_verification_failed"));
          return;
        }
        final token = await api.verifyEmailCode(phone, code);
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString("saved_email", email);
        await _saveToken(token);
      }
    } catch (e) {
      setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _testConnection() async {
    setState(() => connectionStatus = null);
    try {
      final resp = await http.get(Uri.parse("$apiBaseUrl/health"));
      if (resp.statusCode == 200) {
        setState(() => connectionStatus = "OK");
      } else {
        setState(() => connectionStatus = "HTTP ${resp.statusCode}");
      }
    } catch (e) {
      setState(() => connectionStatus = "Failed: ${e.toString()}");
    }
  }

  Future<void> _saveToken(String token) async {
    api.token = token;
    await _writeAuthToken(token);
    final prefs = await SharedPreferences.getInstance();
    try {
      final profile = await api.getCurrentUser();
      final key = _deriveUserKey(profile);
      currentUserKey.value = key;
      await prefs.setString("current_user_key", key);
    } catch (_) {}
    isLoggedIn.value = true;
    if (mounted) {
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const StartReportScreen()));
    }
  }

  Future<bool> _showTermsAndAccept() async {
    bool accepted = false;
    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(t(context, "terms_title")),
        content: SingleChildScrollView(
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "This is a beta, experimental application provided \"as is\" without warranties of any kind. "
                  "You are solely responsible for the accuracy and legality of any data you upload. "
                  "All rights, title, and interest in all uploaded content remain with the creator and/or the uploader. "
                  "The application operator is not liable for any loss, damage, or claims arising from use of the app "
                  "or generated reports. By continuing, you agree to these terms.",
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Checkbox(
                      value: accepted,
                      onChanged: (value) {
                        accepted = value ?? false;
                        (context as Element).markNeedsBuild();
                      },
                    ),
                    Expanded(child: Text(t(context, "terms_accept"))),
                  ],
                ),
              ],
            ),
          ),
        ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(t(context, "terms_decline_button")),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(accepted),
              child: Text(t(context, "terms_accept_button")),
            ),
          ],
        );
      },
    );
    return result ?? false;
  }

  Future<String?> _promptForCode() async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t(context, "verification_code_title")),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(labelText: t(context, "verification_code_label")),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(null),
            child: Text(t(context, "cancel_button")),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: Text(t(context, "verify_code_button")),
          ),
        ],
      ),
    );
    return result;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(t(context, "login_title")), actions: appBarActions(context)),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: phoneController,
              textDirection: _textDirection(context),
              textAlign: _textAlign(context),
              decoration: InputDecoration(labelText: t(context, "phone_label")),
            ),
            TextField(
              controller: emailController,
              readOnly: !emailEditable,
              textDirection: TextDirection.ltr,
              textAlign: TextAlign.left,
              decoration: InputDecoration(labelText: t(context, "email_label")),
            ),
            TextField(
              controller: passwordController,
              textDirection: _textDirection(context),
              textAlign: _textAlign(context),
              decoration: InputDecoration(labelText: t(context, "password_label")),
              obscureText: true,
            ),
            const SizedBox(height: 16),
            if (error != null) Text(error!, style: const TextStyle(color: Colors.red)),
            ElevatedButton(
              onPressed: loading ? null : _auth,
              child: Text(t(context, "login_button")),
            ),
            const SizedBox(height: 24),
            const Divider(),
            Text(
              "API: $apiBaseUrl",
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _testConnection,
              icon: const Icon(Icons.network_check),
              label: const Text("Test Connection"),
            ),
            if (connectionStatus != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(connectionStatus!, style: Theme.of(context).textTheme.bodySmall),
              ),
          ],
        ),
      ),
    );
  }
}

class StartReportScreen extends StatefulWidget {
  const StartReportScreen({super.key});

  @override
  State<StartReportScreen> createState() => _StartReportScreenState();
}

class _StartReportScreenState extends State<StartReportScreen> {
  final locationController = TextEditingController();
  String? error;
  List<TemplateInfo> templates = [];
  String? selectedTemplateKey;
  List<String> recentLocations = [];
  List<String> locationHistory = [];
  bool loading = false;
  @override
  void initState() {
    super.initState();
    _loadTemplates();
    _loadLocations();
    _loadLocationHistory();
  }

  Future<void> _loadTemplates() async {
    try {
      final list = await api.listTemplates();
      if (mounted) {
        setState(() {
          templates = list;
          selectedTemplateKey = list.isNotEmpty ? list.first.key : null;
        });
      }
    } catch (e) {
      setState(() => error = e.toString());
    }
  }

  Future<void> _loadLocations() async {
    try {
      final list = await api.listLocations();
      if (mounted) {
        final cleaned = list.map(HistoryStore.normalizeValue).where((e) => e.isNotEmpty).toList();
        setState(() => recentLocations = cleaned);
      }
    } catch (e) {
      setState(() => error = e.toString());
    }
  }

  Future<void> _loadLocationHistory() async {
    final list = await HistoryStore.getHistory("history_locations", userKey: currentUserKey.value);
    if (mounted) {
      setState(() => locationHistory = list);
    }
  }

  Future<ActiveSessionData?> _getActiveSession() async {
    try {
      return await api.getActiveSession();
    } catch (_) {
      return null;
    }
  }

  Future<void> _start() async {
    try {
      final existing = await _getActiveSession();
      if (existing != null) {
        if (mounted) {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => ContactsScreen(
                initialLocation: existing.location,
                templateKey: existing.templateKey,
                templateTitle: appLocale.value.languageCode == "he"
                    ? existing.titleHe
                    : existing.title,
              ),
            ),
          );
        }
        return;
      }
      if (selectedTemplateKey == null) {
        setState(() => error = t(context, "error_no_template"));
        return;
      }
      final template = templates.firstWhere((t) => t.key == selectedTemplateKey,
          orElse: () => templates.first);
      final templateTitle =
          appLocale.value.languageCode == "he" ? template.titleHe : template.title;
      await HistoryStore.addValue(
        "history_locations",
        locationController.text,
        userKey: currentUserKey.value,
      );
      await api.startReport(locationController.text.trim(), selectedTemplateKey!);
      if (mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ContactsScreen(
              initialLocation: locationController.text.trim(),
              templateKey: selectedTemplateKey!,
              templateTitle: templateTitle,
            ),
          ),
        );
      }
    } catch (e) {
      setState(() => error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(t(context, "start_report_title")),
        actions: appBarActions(context, showLogout: true),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Autocomplete<String>(
              optionsBuilder: (value) {
                final allLocations = {...recentLocations, ...locationHistory}.toList();
                if (value.text.isEmpty) {
                  return allLocations;
                }
                return allLocations.where(
                  (option) => option.toLowerCase().contains(value.text.toLowerCase()),
                );
              },
              fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
                controller.text = locationController.text;
                controller.selection = TextSelection.fromPosition(
                  TextPosition(offset: controller.text.length),
                );
                controller.addListener(() {
                  locationController.text = controller.text;
                });
                return TextField(
                  controller: controller,
                  focusNode: focusNode,
                  textDirection: _textDirection(context),
                  textAlign: _textAlign(context),
                  decoration: InputDecoration(labelText: t(context, "location_label")),
                );
              },
            ),
            if (recentLocations.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  "${t(context, "saved_locations_label")}: ${recentLocations.join(", ")}",
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            const SizedBox(height: 12),
            if (templates.isNotEmpty)
              DropdownButtonFormField<String>(
                value: selectedTemplateKey,
                decoration: InputDecoration(labelText: t(context, "template_label")),
                items: templates
                    .map((t) => DropdownMenuItem(
                          value: t.key,
                          enabled: t.key == "INSPECTION_REPORT",
                          child: Text(
                            appLocale.value.languageCode == "he"
                                ? t.titleHe
                                : t.title,
                            style: t.key == "INSPECTION_REPORT"
                                ? null
                                : TextStyle(color: Theme.of(context).disabledColor),
                          ),
                        ))
                    .toList(),
                onChanged: (value) => setState(() => selectedTemplateKey = value),
              ),
            const SizedBox(height: 16),
            if (error != null) Text(error!, style: const TextStyle(color: Colors.red)),
            ElevatedButton(onPressed: _start, child: Text(t(context, "start_button"))),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const RecentReportsScreen()),
              ),
              child: Text(t(context, "recent_reports_button")),
            ),
          ],
        ),
      ),
    );
  }
}

class ContactsScreen extends StatefulWidget {
  const ContactsScreen({
    super.key,
    required this.initialLocation,
    required this.templateKey,
    required this.templateTitle,
  });

  final String initialLocation;
  final String templateKey;
  final String templateTitle;

  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen> {
  List<ContactInfo> contacts = [];
  final Set<String> attendees = {};
  final Set<String> distribution = {};
  String? error;
  bool loading = false;

  final nameController = TextEditingController();
  final emailController = TextEditingController();
  List<String> nameHistory = [];
  List<String> emailHistory = [];

  @override
  void initState() {
    super.initState();
    _loadContacts();
    _loadHistory();
    _loadExistingSelection();
  }

  Future<void> _loadContacts() async {
    try {
      final list = await api.listContacts();
      if (mounted) {
        setState(() => contacts = list);
      }
    } catch (e) {
      setState(() => error = e.toString());
    }
  }

  Future<void> _loadHistory() async {
    final names = await HistoryStore.getHistory("history_contact_names", userKey: currentUserKey.value);
    final emails = await HistoryStore.getHistory("history_contact_emails", userKey: currentUserKey.value);
    if (mounted) {
      setState(() {
        nameHistory = names;
        emailHistory = emails;
      });
    }
  }

  Future<void> _loadExistingSelection() async {
    try {
      final session = await api.getActiveSession();
      if (!mounted) return;
      setState(() {
        attendees
          ..clear()
          ..addAll(session.attendees);
        distribution
          ..clear()
          ..addAll(session.distributionList);
      });
    } catch (_) {}
  }

  bool _isValidEmail(String value) {
    final email = value.trim();
    if (email.isEmpty) return false;
    final asciiOnly = RegExp(r"^[\x00-\x7F]+$");
    final pattern = RegExp(r"^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$");
    return asciiOnly.hasMatch(email) && pattern.hasMatch(email);
  }

  Future<void> _addContact() async {
    try {
      final name = nameController.text.trim();
      final email = emailController.text.trim();
      if (name.isEmpty || email.isEmpty) {
        setState(() => error = t(context, "error_name_email_required"));
        return;
      }
      if (!_isValidEmail(email)) {
        setState(() => error = t(context, "error_email_invalid"));
        return;
      }
      final contact = await api.addContact(name: name, email: email);
      await HistoryStore.addValue("history_contact_names", name, userKey: currentUserKey.value);
      await HistoryStore.addValue("history_contact_emails", email, userKey: currentUserKey.value);
      setState(() {
        contacts.add(contact);
        nameController.clear();
        emailController.clear();
      });
    } catch (e) {
      setState(() => error = e.toString());
    }
  }

  Future<void> _pickFromPhone() async {
    final permitted = await FlutterContacts.requestPermission();
    if (!permitted) {
      setState(() => error = t(context, "contacts_permission_denied"));
      return;
    }
    final phoneContacts = await FlutterContacts.getContacts(withProperties: true);
    if (phoneContacts.isEmpty) {
      setState(() => error = t(context, "contacts_empty_phone"));
      return;
    }
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        final searchController = TextEditingController();
        List<Contact> filtered = List.from(phoneContacts);
        return StatefulBuilder(
          builder: (context, setStateSheet) {
            void filter(String q) {
              setStateSheet(() {
                filtered = phoneContacts
                    .where((c) => c.displayName.toLowerCase().contains(q.toLowerCase()))
                    .toList();
              });
            }

            return Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  TextField(
                    controller: searchController,
                    textDirection: _textDirection(context),
                    textAlign: _textAlign(context),
                    decoration: InputDecoration(labelText: t(context, "search_contacts_label")),
                    onChanged: filter,
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListView.builder(
                      itemCount: filtered.length,
                      itemBuilder: (context, index) {
                        final c = filtered[index];
                        final email = c.emails.isNotEmpty ? c.emails.first.address : "";
                        return ListTile(
                          title: Text(c.displayName),
                          subtitle: Text(email),
                          onTap: () {
                            nameController.text = c.displayName;
                            if (email.isNotEmpty) {
                              emailController.text = email;
                            }
                            Navigator.of(context).pop();
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _continue() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      await api.setReportContacts(
        attendees: attendees.toList(),
        distributionList: distribution.toList(),
      );
      if (mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => AddItemScreen(
              location: widget.initialLocation,
              templateTitle: widget.templateTitle,
            ),
          ),
        );
      }
    } catch (e) {
      final message = e.toString();
      if (message.contains("No active report")) {
        try {
          await api.startReport(widget.initialLocation, widget.templateKey);
          await api.setReportContacts(
            attendees: attendees.toList(),
            distributionList: distribution.toList(),
          );
          if (mounted) {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => AddItemScreen(
                  location: widget.initialLocation,
                  templateTitle: widget.templateTitle,
                ),
              ),
            );
          }
          return;
        } catch (inner) {
          setState(() => error = inner.toString());
        }
      } else {
        setState(() => error = message);
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(t(context, "contacts_title")),
        actions: appBarActions(context, showLogout: true),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            if (error != null) Text(error!, style: const TextStyle(color: Colors.red)),
            Autocomplete<String>(
              optionsBuilder: (value) {
                if (value.text.isEmpty) {
                  return nameHistory;
                }
                return nameHistory.where(
                  (option) => option.toLowerCase().contains(value.text.toLowerCase()),
                );
              },
              fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
                controller.text = nameController.text;
                controller.selection = TextSelection.fromPosition(
                  TextPosition(offset: controller.text.length),
                );
                controller.addListener(() {
                  nameController.text = controller.text;
                });
                return TextField(
                  controller: controller,
                  focusNode: focusNode,
                  textDirection: _textDirection(context),
                  textAlign: _textAlign(context),
                  decoration: InputDecoration(labelText: t(context, "name_label")),
                );
              },
            ),
            Autocomplete<String>(
              optionsBuilder: (value) {
                if (value.text.isEmpty) {
                  return emailHistory;
                }
                return emailHistory.where(
                  (option) => option.toLowerCase().contains(value.text.toLowerCase()),
                );
              },
              fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
                controller.text = emailController.text;
                controller.selection = TextSelection.fromPosition(
                  TextPosition(offset: controller.text.length),
                );
                controller.addListener(() {
                  emailController.text = controller.text;
                });
                return TextField(
                  controller: controller,
                  focusNode: focusNode,
                  textDirection: TextDirection.ltr,
                  textAlign: TextAlign.left,
                  decoration: InputDecoration(labelText: t(context, "email_label")),
                );
              },
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                ElevatedButton(onPressed: _addContact, child: Text(t(context, "add_contact_button"))),
                const SizedBox(width: 8),
                OutlinedButton(onPressed: _pickFromPhone, child: Text(t(context, "pick_from_phone_button"))),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView.builder(
                itemCount: contacts.length,
                itemBuilder: (context, index) {
                  final c = contacts[index];
                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text("${c.name} (${c.email})"),
                          Row(
                            children: [
                              Expanded(
                                child: CheckboxListTile(
                                  title: Text(t(context, "attendee_label")),
                                  value: attendees.contains(c.id),
                                  onChanged: (value) {
                                    setState(() {
                                      if (value == true) {
                                        attendees.add(c.id);
                                      } else {
                                        attendees.remove(c.id);
                                      }
                                    });
                                  },
                                ),
                              ),
                              Expanded(
                                child: CheckboxListTile(
                                  title: Text(t(context, "recipient_label")),
                                  value: distribution.contains(c.id),
                                  onChanged: (value) {
                                    setState(() {
                                      if (value == true) {
                                        distribution.add(c.id);
                                      } else {
                                        distribution.remove(c.id);
                                      }
                                    });
                                  },
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            ElevatedButton(
              onPressed: loading ? null : _continue,
              child: Text(t(context, "continue_button")),
            ),
          ],
        ),
      ),
    );
  }
}

class RecentReportsScreen extends StatefulWidget {
  const RecentReportsScreen({super.key});

  @override
  State<RecentReportsScreen> createState() => _RecentReportsScreenState();
}

class _RecentReportsScreenState extends State<RecentReportsScreen> {
  List<ReportSummary> reports = [];
  String? error;
  bool loading = false;

  @override
  void initState() {
    super.initState();
    _loadReports();
  }

  Future<void> _loadReports() async {
    try {
      final list = await api.listRecentReports();
      if (mounted) {
        setState(() => reports = list);
      }
    } catch (e) {
      setState(() => error = e.toString());
    }
  }

  Future<void> _openForEdit(ReportSummary report) async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      await api.openReport(report.reportId);
      if (mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => AddItemScreen(
              location: report.location,
              templateTitle: appLocale.value.languageCode == "he"
                  ? report.titleHe
                  : report.title,
            ),
          ),
        );
      }
    } catch (e) {
      setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _organize(ReportSummary report) async {
    final folderController = TextEditingController(text: report.folder);
    final tagsController = TextEditingController(text: report.tags.join(", "));
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t(context, "organize_report_button")),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: folderController,
              textDirection: _textDirection(context),
              textAlign: _textAlign(context),
              decoration: InputDecoration(labelText: t(context, "folder_label")),
            ),
            TextField(
              controller: tagsController,
              textDirection: _textDirection(context),
              textAlign: _textAlign(context),
              decoration: InputDecoration(labelText: t(context, "tags_label")),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(t(context, "cancel_button")),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(t(context, "save_button")),
          ),
        ],
      ),
    );
    if (result != true) return;
    final tags = tagsController.text
        .split(",")
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty)
        .toList();
    await api.organizeReport(report.reportId, folderController.text.trim(), tags);
    await _loadReports();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(t(context, "recent_reports_title")),
        actions: appBarActions(context, showLogout: true),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            if (error != null) Text(error!, style: const TextStyle(color: Colors.red)),
            if (reports.isEmpty)
              Text(t(context, "no_reports_yet"))
            else
              Expanded(
                child: ListView.builder(
                  itemCount: reports.length,
                  itemBuilder: (context, index) {
                    final r = reports[index];
                    final subtitleParts = <String>[
                      r.createdAt,
                      if (r.location.isNotEmpty) r.location,
                      if (r.folder.isNotEmpty) "📁 ${r.folder}",
                      if (r.tags.isNotEmpty) "🏷 ${r.tags.join(", ")}",
                    ];
                    return Card(
                      child: ListTile(
                        title: Text(appLocale.value.languageCode == "he"
                            ? r.titleHe
                            : r.title),
                        subtitle: Text(subtitleParts.join(" • ")),
                        trailing: Wrap(
                          spacing: 8,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit),
                              onPressed: loading ? null : () => _openForEdit(r),
                              tooltip: t(context, "edit_report_button"),
                            ),
                            IconButton(
                              icon: const Icon(Icons.folder),
                              onPressed: loading ? null : () => _organize(r),
                              tooltip: t(context, "organize_report_button"),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class AddItemScreen extends StatefulWidget {
  const AddItemScreen({super.key, this.location, this.templateTitle});

  final String? location;
  final String? templateTitle;

  @override
  State<AddItemScreen> createState() => _AddItemScreenState();
}

class _AddItemScreenState extends State<AddItemScreen> {
  final descriptionController = TextEditingController();
  final notesController = TextEditingController();
  final FocusNode descriptionFocus = FocusNode();
  final FocusNode notesFocus = FocusNode();
  File? photo;
  String? currentItemId;
  String? activeItemId;
  String? error;
  final stt.SpeechToText speech = stt.SpeechToText();
  bool isRecording = false;
  String lastTranscript = "";
  double soundLevel = 0.0;
  String? recordingItemId;
  String? recordingField;
  List<String> descriptionHistory = [];
  List<String> notesHistory = [];
  List<ReportItemData> existingItems = [];
  String? editingItemId;
  String? speechLocaleId;
  Map<String, List<ReportPhotoData>> itemPhotos = {};
  String? sessionLocation;
  String? sessionTitle;
  bool _initialItemCreated = false;

  @override
  void initState() {
    super.initState();
    _loadHistory();
    _loadExistingItems();
  }

  @override
  void dispose() {
    descriptionController.dispose();
    descriptionFocus.dispose();
    notesController.dispose();
    notesFocus.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    if (mounted) {
      setState(() {
        descriptionHistory = [];
        notesHistory = [];
      });
    }
  }

  Future<void> _loadExistingItems() async {
    try {
      final session = await api.getActiveSession();
      final grouped = <String, List<ReportPhotoData>>{};
      for (final photo in session.photos) {
        if (photo.itemId == null) continue;
        grouped.putIfAbsent(photo.itemId!, () => []).add(photo);
      }
      if (mounted) {
        setState(() {
          existingItems = session.items;
          itemPhotos = grouped;
          sessionLocation = session.location;
          sessionTitle = appLocale.value.languageCode == "he" ? session.titleHe : session.title;
          if (activeItemId != null && session.items.every((item) => item.id != activeItemId)) {
            activeItemId = null;
          }
        });
        if (session.items.isEmpty && !_initialItemCreated) {
          _initialItemCreated = true;
          await _createEmptyItem();
        }
      }
    } catch (_) {}
  }

  bool _itemHasPhoto(String? itemId) {
    if (itemId == null) return false;
    final photos = itemPhotos[itemId] ?? [];
    return photos.isNotEmpty;
  }

  bool _itemHasContent(ReportItemData item) {
    return item.description.trim().isNotEmpty ||
        item.notes.trim().isNotEmpty ||
        _itemHasPhoto(item.id);
  }

  Future<void> _createEmptyItem() async {
    try {
      final id = await api.addItem("", "", allowEmpty: true);
      setState(() {
        currentItemId = id;
        activeItemId = id;
        editingItemId = id;
        descriptionController.clear();
        notesController.clear();
        lastTranscript = "";
      });
      await _loadExistingItems();
    } catch (e) {
      setState(() => error = e.toString());
    }
  }

  Future<String?> _resolveSpeechLocale() async {
    try {
      final lang = Localizations.localeOf(context).languageCode.toLowerCase();
      final locales = await speech.locales();
      api.sendDebugLog("RESOLVE_LOCALE_START", {
        "current_lang": lang,
        "device_locales": locales.map((l) => "${l.localeId}:${l.name}").toList()
      });
      if (locales.isEmpty) return null;

      // 1. Try exact match for language code (e.g. "he" or "he-IL")
      for (final l in locales) {
        final id = l.localeId.toLowerCase();
        if (id == lang || id == "${lang}_il" || id == "${lang}-il") {
          api.sendDebugLog("RESOLVE_LOCALE_EXACT_MATCH", {"id": l.localeId});
          return l.localeId;
        }
      }

      // 2. Try prefix match
      final match = locales.where((l) => l.localeId.toLowerCase().startsWith(lang)).toList();
      if (match.isNotEmpty) {
        api.sendDebugLog("RESOLVE_LOCALE_PREFIX_MATCH", {"id": match.first.localeId});
        return match.first.localeId;
      }

      // 3. Special case for Hebrew (some devices use legacy "iw")
      if (lang == "he") {
        final hebrewMatch = locales.where((l) {
          final id = l.localeId.toLowerCase();
          return id.startsWith("he") || id.startsWith("iw");
        }).toList();
        if (hebrewMatch.isNotEmpty) {
          api.sendDebugLog("RESOLVE_LOCALE_HEBREW_MATCH", {"id": hebrewMatch.first.localeId});
          return hebrewMatch.first.localeId;
        }
        api.sendDebugLog("RESOLVE_LOCALE_HEBREW_MISSING", {"available": locales.length});
        return null;
      }

      return locales.first.localeId;
    } catch (e) {
      api.sendDebugLog("RESOLVE_LOCALE_EXCEPTION", {"error": e.toString()});
      return null;
    }
  }


  Future<bool> _savePhotoToGallery(String path) async {
    if (kIsWeb) return false;
    try {
      final permission = await PhotoManager.requestPermissionExtend();
      if (!permission.isAuth) return false;
      await PhotoManager.editor.saveImageWithPath(path);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<String?> _backupPhotoToDevice(String path) async {
    if (kIsWeb) return null;
    try {
      // Android emulator/device path maps to: /data/data/<package>/app_flutter/...
      final dir = await getApplicationDocumentsDirectory();
      final backupDir = Directory("${dir.path}/photo_backups");
      if (!await backupDir.exists()) {
        await backupDir.create(recursive: true);
      }
      final dotIndex = path.lastIndexOf(".");
      final ext = dotIndex == -1 ? "" : path.substring(dotIndex);
      final filename = "photo_${DateTime.now().millisecondsSinceEpoch}$ext";
      final target = "${backupDir.path}/$filename";
      await File(path).copy(target);
      return target;
    } catch (_) {}
    return null;
  }

  void _cleanupTempMedia(String path) {
    if (kIsWeb) return;
    try {
      final file = File(path);
      final name = file.uri.pathSegments.isNotEmpty ? file.uri.pathSegments.last : "";
      final parent = file.parent.path;
      if (name.startsWith("res_timestamp") &&
          parent.endsWith("${Platform.pathSeparator}app_flutter")) {
        file.deleteSync();
      }
    } catch (_) {}
  }

  Widget _buildAttachments() {
    if (activeItemId == null) return const SizedBox.shrink();
    final photos = itemPhotos[activeItemId] ?? [];
    if (photos.isEmpty) {
      return const SizedBox.shrink();
    }
    final headers = api.token != null ? {"Authorization": "Bearer ${api.token}"} : <String, String>{};
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        Text(t(context, "attached_media_label")),
        if (photos.isNotEmpty) ...[
          const SizedBox(height: 6),
          SizedBox(
            height: 80,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: photos.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final photo = photos[index];
                final url = "$apiBaseUrl/reports/photo/${photo.id}";
                return ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Image.network(
                    url,
                    headers: headers,
                    width: 80,
                    height: 80,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      return Container(
                        width: 80,
                        height: 80,
                        color: Theme.of(context).colorScheme.surfaceVariant,
                        alignment: Alignment.center,
                        child: const Icon(Icons.broken_image),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ],
    );
  }

  ReportItemData? _findItem(String itemId) {
    for (final item in existingItems) {
      if (item.id == itemId) return item;
    }
    return null;
  }

  Future<void> _applyTranscriptToItem(String itemId, String transcript) async {
    final item = _findItem(itemId);
    if (item == null) {
      setState(() => error = t(context, "transcription_error"));
      return;
    }
    final newNotes = item.notes.isEmpty ? transcript : "${item.notes}\n$transcript";
    await api.updateItem(itemId, item.description, newNotes);
    if (editingItemId == itemId) {
      setState(() {
        notesController.text = newNotes;
        notesController.selection = TextSelection.fromPosition(
          TextPosition(offset: notesController.text.length),
        );
      });
    }
    await _loadExistingItems();
  }

  Future<bool> _createItemFromDraftForMedia() async {
    final descriptionTrimmed = descriptionController.text.trim();
    final notesTrimmed = notesController.text.trim();
    if (descriptionTrimmed.isEmpty && notesTrimmed.isEmpty) {
      return false;
    }
    if (descriptionTrimmed.isEmpty && notesTrimmed.isNotEmpty) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(t(context, "confirm_notes_only_title")),
          content: Text(t(context, "confirm_notes_only_body")),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(t(context, "confirm_notes_only_no")),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(t(context, "confirm_notes_only_yes")),
            ),
          ],
        ),
      );
      if (proceed != true) {
        return false;
      }
    }
    final id = await api.addItem(descriptionTrimmed, notesTrimmed);
    setState(() {
      currentItemId = id;
      activeItemId = id;
      editingItemId = id;
    });
    await _loadExistingItems();
    return true;
  }

  Future<String?> _promptForItemSelection() async {
    if (existingItems.isEmpty) return null;
    if (!mounted) return null;
    return showModalBottomSheet<String>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(t(context, "select_item_title")),
              ),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: existingItems.length,
                  itemBuilder: (context, index) {
                    final item = existingItems[index];
                    final label = item.description.isNotEmpty
                        ? item.description
                        : (item.notes.isNotEmpty ? item.notes : item.number);
                    return ListTile(
                      title: Text("${item.number}  $label"),
                      onTap: () => Navigator.of(context).pop(item.id),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<bool> _ensureActiveItemForMedia() async {
    if (activeItemId != null) return true;
    if (existingItems.isNotEmpty) {
      final selected = await _promptForItemSelection();
      if (selected != null) {
        setState(() => activeItemId = selected);
        return true;
      }
    }
    await _createEmptyItem();
    return activeItemId != null;
  }

  Future<void> _addItem() async {
    try {
      final descriptionTrimmed = descriptionController.text.trim();
      final notesTrimmed = notesController.text.trim();
      if (descriptionTrimmed.isEmpty && notesTrimmed.isEmpty) {
        if (_itemHasPhoto(activeItemId)) {
          await _createEmptyItem();
          return;
        }
        setState(() => error = t(context, "error_item_empty"));
        return;
      }
      if (descriptionTrimmed.isEmpty && notesTrimmed.isNotEmpty) {
        final proceed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(t(context, "confirm_notes_only_title")),
            content: Text(t(context, "confirm_notes_only_body")),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(t(context, "confirm_notes_only_no")),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: Text(t(context, "confirm_notes_only_yes")),
              ),
            ],
          ),
        );
        if (proceed != true) return;
      }
      if (editingItemId != null) {
        await api.updateItem(
          editingItemId!,
          descriptionTrimmed,
          notesTrimmed,
        );
        setState(() {
          editingItemId = null;
          descriptionController.clear();
          notesController.clear();
          lastTranscript = "";
        });
        await _loadExistingItems();
        return;
      }
      final id = await api.addItem(
        descriptionTrimmed,
        notesTrimmed,
      );
      setState(() {
        currentItemId = id;
        activeItemId = null;
        descriptionController.clear();
        notesController.clear();
        lastTranscript = "";
      });
      await _loadExistingItems();
    } catch (e) {
      setState(() => error = e.toString());
    }
  }

  Future<void> _takePhoto() async {
    if (!await _ensureActiveItemForMedia()) {
      return;
    }
    final camOk = await Permission.camera.request();
    if (!camOk.isGranted) {
      setState(() => error = t(context, "permission_camera_denied"));
      return;
    }
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.camera);
    if (picked != null) {
      setState(() => photo = File(picked.path));
      final saved = await _savePhotoToGallery(picked.path);
      String? backupPath;
      if (!saved) {
        backupPath = await _backupPhotoToDevice(picked.path);
      }
      _cleanupTempMedia(picked.path);
      await _uploadPhotoFile(File(picked.path), activeItemId!, backupPath: backupPath);
    }
  }

  Future<void> _takePhotoForItem(String itemId) async {
    final camOk = await Permission.camera.request();
    if (!camOk.isGranted) {
      setState(() => error = t(context, "permission_camera_denied"));
      return;
    }
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.camera);
    if (picked == null) return;
    try {
      final saved = await _savePhotoToGallery(picked.path);
      String? backupPath;
      if (!saved) {
        backupPath = await _backupPhotoToDevice(picked.path);
      }
      _cleanupTempMedia(picked.path);
      await _uploadPhotoFile(File(picked.path), itemId, backupPath: backupPath);
      await _loadExistingItems();
    } catch (e) {
      setState(() => error = e.toString());
    }
  }

  Future<void> _uploadPhoto() async {
    if (!await _ensureActiveItemForMedia()) {
      return;
    }
    final photosOk = await Permission.photos.request();
    if (!photosOk.isGranted) {
      setState(() => error = t(context, "permission_photos_denied"));
      return;
    }
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked == null) return;
    final saved = await _savePhotoToGallery(picked.path);
    String? backupPath;
    if (!saved) {
      backupPath = await _backupPhotoToDevice(picked.path);
    }
    _cleanupTempMedia(picked.path);
    await _uploadPhotoFile(File(picked.path), activeItemId!, backupPath: backupPath);
  }

  Future<void> _uploadPhotoFile(File file, String itemId, {String? backupPath}) async {
    try {
      await api.uploadPhoto(file, itemId: itemId);
      if (mounted) {
        setState(() => photo = null);
      }
      if (backupPath != null) {
        try {
          await File(backupPath).delete();
        } catch (_) {}
      }
      await _loadExistingItems();
    } catch (e) {
      setState(() => error = e.toString());
    }
  }

  Future<void> _finalize() async {
    try {
      final committed = await _commitDraftItemBeforeFinalize();
      if (!committed) return;
      if (existingItems.isEmpty) {
        final proceed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(t(context, "confirm_empty_report_title")),
            content: Text(t(context, "confirm_empty_report_body")),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(t(context, "confirm_empty_report_no")),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: Text(t(context, "confirm_empty_report_yes")),
              ),
            ],
          ),
        );
        if (proceed != true) return;
      }
      final now = DateTime.now();
      final datePart =
          "${now.year.toString().padLeft(4, "0")}${now.month.toString().padLeft(2, "0")}${now.day.toString().padLeft(2, "0")}";
      final timePart =
          "${now.hour.toString().padLeft(2, "0")}${now.minute.toString().padLeft(2, "0")}";
      final templatePart =
          _safeFilePart(widget.templateTitle ?? sessionTitle ?? t(context, "add_item_title"));
      final locationPart = _safeFilePart(widget.location ?? sessionLocation ?? "");
      final filenameParts = [
        if (templatePart.isNotEmpty) templatePart,
        if (locationPart.isNotEmpty) locationPart,
        "$datePart-$timePart",
      ];
      final filename = filenameParts.join("_");
      final path = await api.finalizeAndSave(filename: filename);
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => DoneScreen(filePath: path)),
        );
      }
    } catch (e) {
      setState(() => error = e.toString());
    }
  }

  Future<void> _cancelReport() async {
    final proceed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t(context, "cancel_report_title")),
        content: Text(t(context, "cancel_report_body")),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(t(context, "cancel_button")),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(t(context, "cancel_report_confirm")),
          ),
        ],
      ),
    );
    if (proceed != true) return;
    try {
      await api.cancelReport();
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const StartReportScreen()),
          (route) => false,
        );
      }
    } catch (e) {
      setState(() => error = e.toString());
    }
  }

  Future<bool> _commitDraftItemBeforeFinalize() async {
    String description = descriptionController.text.trim();
    String notes = notesController.text.trim();
    if (description.isEmpty && notes.isEmpty) {
      return true;
    }
    if (description.isEmpty && notes.isNotEmpty) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(t(context, "confirm_notes_only_title")),
          content: Text(t(context, "confirm_notes_only_body")),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(t(context, "confirm_notes_only_no")),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(t(context, "confirm_notes_only_yes")),
            ),
          ],
        ),
      );
      if (proceed != true) {
        return false;
      }
    }
    if (editingItemId != null) {
      await api.updateItem(editingItemId!, description, notes);
      setState(() {
        editingItemId = null;
        descriptionController.clear();
        notesController.clear();
      });
      await _loadExistingItems();
      return true;
    }
    final id = await api.addItem(description, notes);
    setState(() {
      currentItemId = id;
      activeItemId = id;
      descriptionController.clear();
      notesController.clear();
    });
    await _loadExistingItems();
    return true;
  }

  Future<void> _toggleRecording({String? targetItemId, String? targetField}) async {
    try {
      if (!isRecording) {
        if (error != null) {
          setState(() => error = null);
        }
        api.sendDebugLog("STT_START_ATTEMPT", {"field": targetField});
        final micOk = await Permission.microphone.request();
        api.sendDebugLog("MIC_PERMISSION", {"granted": micOk.isGranted});
        if (!micOk.isGranted) {
          setState(() => error = t(context, "transcription_error"));
          return;
        }

        final available = await speech.initialize(
          onStatus: (status) {
            debugPrint("STT Status: $status");
            api.sendDebugLog("STT_STATUS", {"status": status});
          },
          onError: (err) {
            debugPrint("STT Error: ${err.errorMsg}");
            api.sendDebugLog("STT_ERROR", {"msg": err.errorMsg, "permanent": err.permanent});
            if (mounted) {
              setState(() => error = t(context, "transcription_error"));
            }
          },
          debugLogging: true,
        );

        api.sendDebugLog("STT_INITIALIZED", {"available": available});
        if (!available) {
          setState(() => error = t(context, "speech_not_available"));
          return;
        }

        speechLocaleId = await _resolveSpeechLocale();
        api.sendDebugLog("STT_LOCALE", {"locale": speechLocaleId});
        if (speechLocaleId == null) {
          setState(() => error = t(context, "speech_not_available"));
          return;
        }

        setState(() {
          isRecording = true;
          lastTranscript = "";
          recordingItemId = targetItemId;
          recordingField = targetField;
        });

        await speech.listen(
          localeId: speechLocaleId!,
          onResult: (result) {
            api.sendDebugLog("STT_RESULT", {
              "words": result.recognizedWords,
              "final": result.finalResult,
              "confidence": result.confidence
            });
            if (mounted) {
              setState(() {
                lastTranscript = result.recognizedWords;
                if (recordingItemId == null) {
                  if (recordingField == "description") {
                    descriptionController.text = lastTranscript;
                    descriptionController.selection = TextSelection.fromPosition(
                      TextPosition(offset: descriptionController.text.length),
                    );
                  } else {
                    notesController.text = lastTranscript;
                    notesController.selection = TextSelection.fromPosition(
                      TextPosition(offset: notesController.text.length),
                    );
                  }
                }
              });
            }
          },
          onSoundLevelChange: (level) {
            if (mounted) setState(() => soundLevel = level);
          },
          cancelOnError: false,
          partialResults: true,
          listenMode: stt.ListenMode.dictation,
          listenFor: const Duration(seconds: 30),
          pauseFor: const Duration(seconds: 10),
        );
      } else {
        api.sendDebugLog("STT_STOP_REQUEST", {});
        await speech.stop();
        final target = recordingItemId;
        if (mounted) {
          setState(() {
            isRecording = false;
            recordingItemId = null;
            recordingField = null;
          });
        }
        if (target != null && lastTranscript.isNotEmpty) {
          await _applyTranscriptToItem(target, lastTranscript);
        }
        if (mounted) {
          setState(() => soundLevel = 0.0);
        }
      }
    } catch (e) {
      debugPrint("Toggle recording error: $e");
      api.sendDebugLog("TOGGLE_RECORDING_EXCEPTION", {"error": e.toString()});
      if (mounted) {
        setState(() {
          isRecording = false;
          error = t(context, "transcription_error");
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(t(context, "add_item_title")),
        actions: appBarActions(
          context,
          showLogout: true,
          showCancelReport: true,
          onSelected: (value) {
            if (value == "cancel_report") {
              _cancelReport();
            }
          },
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
            if (existingItems.where(_itemHasContent).isNotEmpty)
              SizedBox(
                height: 120,
                child: ListView.builder(
                  itemCount: existingItems.where(_itemHasContent).length,
                  itemBuilder: (context, index) {
                    final item = existingItems.where(_itemHasContent).toList()[index];
                    return ListTile(
                      title: Text("${item.number}. ${item.description}"),
                      subtitle: Text(item.notes),
                      selected: item.id == activeItemId,
                      selectedTileColor: Theme.of(context).colorScheme.primary.withOpacity(0.08),
                      onTap: () {
                        setState(() {
                          activeItemId = item.id;
                          currentItemId = item.id;
                          editingItemId = item.id;
                          descriptionController.text = item.description;
                          notesController.text = item.notes;
                        });
                      },
                    );
                  },
                ),
              ),
            Autocomplete<String>(
              optionsBuilder: (value) {
                if (value.text.isEmpty) {
                  return descriptionHistory;
                }
                return descriptionHistory.where(
                  (option) => option.toLowerCase().contains(value.text.toLowerCase()),
                );
              },
              fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
                controller.text = descriptionController.text;
                controller.selection = TextSelection.fromPosition(
                  TextPosition(offset: controller.text.length),
                );
                controller.addListener(() {
                  descriptionController.text = controller.text;
                });
                return TextField(
                  controller: controller,
                  focusNode: descriptionFocus,
                  textDirection: _textDirection(context),
                  textAlign: _textAlign(context),
                  keyboardType: TextInputType.multiline,
                  minLines: 3,
                  maxLines: null,
                  decoration: InputDecoration(labelText: t(context, "description_label")),
                  onChanged: (_) {
                    if (error != null) setState(() => error = null);
                  },
                );
              },
            ),
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.photo_camera, size: 18),
                  tooltip: t(context, "take_photo_button"),
                  onPressed: () {
                    descriptionFocus.requestFocus();
                    _takePhoto();
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.photo_library, size: 18),
                  tooltip: t(context, "upload_photo_button"),
                  onPressed: () {
                    descriptionFocus.requestFocus();
                    _uploadPhoto();
                  },
                ),
                IconButton(
                  icon: Icon(isRecording && recordingField == "description" ? Icons.stop : Icons.mic, size: 18),
                  tooltip: isRecording ? t(context, "stop_recording_button") : t(context, "start_recording_button"),
                  onPressed: isRecording && recordingField != "description"
                      ? null
                      : () => _toggleRecording(targetField: "description"),
                ),
                if (isRecording && recordingField == "description")
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: LinearProgressIndicator(
                        value: (soundLevel + 2) / 15, // Normalize rmsDB to 0.0-1.0
                        backgroundColor: Colors.grey[200],
                        valueColor: AlwaysStoppedAnimation<Color>(Theme.of(context).primaryColor),
                      ),
                    ),
                  ),
              ],
            ),
            Autocomplete<String>(
              optionsBuilder: (value) {
                if (value.text.isEmpty) {
                  return notesHistory;
                }
                return notesHistory.where(
                  (option) => option.toLowerCase().contains(value.text.toLowerCase()),
                );
              },
              fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
                controller.text = notesController.text;
                controller.selection = TextSelection.fromPosition(
                  TextPosition(offset: controller.text.length),
                );
                controller.addListener(() {
                  notesController.text = controller.text;
                });
                return TextField(
                  controller: controller,
                  focusNode: notesFocus,
                  textDirection: _textDirection(context),
                  textAlign: _textAlign(context),
                  keyboardType: TextInputType.multiline,
                  minLines: 3,
                  maxLines: null,
                  decoration: InputDecoration(labelText: t(context, "notes_label")),
                  onChanged: (_) {
                    if (error != null) setState(() => error = null);
                  },
                );
              },
            ),
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.photo_camera, size: 18),
                  tooltip: t(context, "take_photo_button"),
                  onPressed: () {
                    notesFocus.requestFocus();
                    _takePhoto();
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.photo_library, size: 18),
                  tooltip: t(context, "upload_photo_button"),
                  onPressed: () {
                    notesFocus.requestFocus();
                    _uploadPhoto();
                  },
                ),
                IconButton(
                  icon: Icon(isRecording && recordingField == "notes" ? Icons.stop : Icons.mic, size: 18),
                  tooltip: isRecording ? t(context, "stop_recording_button") : t(context, "start_recording_button"),
                  onPressed: isRecording && recordingField != "notes"
                      ? null
                      : () => _toggleRecording(targetField: "notes"),
                ),
                if (isRecording && recordingField == "notes")
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: LinearProgressIndicator(
                        value: (soundLevel + 2) / 15, // Normalize rmsDB to 0.0-1.0
                        backgroundColor: Colors.grey[200],
                        valueColor: AlwaysStoppedAnimation<Color>(Theme.of(context).primaryColor),
                      ),
                    ),
                  ),
              ],
            ),
            _buildAttachments(),
            const SizedBox(height: 12),
            if (lastTranscript.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text("${t(context, "transcription_label")}: $lastTranscript"),
              ),
            const SizedBox(height: 12),
            ElevatedButton(onPressed: _addItem, child: Text(t(context, "add_item_button"))),
            const SizedBox(height: 12),
            if (error != null) Text(error!, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 8),
            ElevatedButton(onPressed: _finalize, child: Text(t(context, "generate_report_button"))),
          ],
      ),
    );
  }
}

class DoneScreen extends StatelessWidget {
  const DoneScreen({super.key, required this.filePath});

  final String filePath;

  Future<void> _openFile() async {
    await OpenFilex.open(filePath);
  }

  Future<void> _shareFile() async {
    await Share.shareXFiles([XFile(filePath)]);
  }

  Future<void> _saveToDownloads(BuildContext context) async {
    if (kIsWeb || !Platform.isAndroid) {
      return;
    }
    try {
      final storageOk = await Permission.storage.request();
      if (!storageOk.isGranted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(t(context, "permission_storage_denied"))),
        );
        return;
      }
      final filename = filePath.split(Platform.pathSeparator).last;
      final primary = Directory("/storage/emulated/0/Download");
      final fallback = Directory("/sdcard/Download");
      final downloadsDir = await primary.exists() ? primary : fallback;
      if (!await downloadsDir.exists()) {
        throw Exception("Downloads not found");
      }
      final targetPath = "${downloadsDir.path}/$filename";
      await File(filePath).copy(targetPath);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t(context, "report_saved_downloads"))),
      );
    } catch (_) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t(context, "report_save_failed"))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(t(context, "done_title")),
        actions: appBarActions(context, showLogout: true),
      ),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(t(context, "report_generated")),
            const SizedBox(height: 8),
            Text(filePath, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _openFile,
              child: Text(t(context, "open_report_button")),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: _shareFile,
              child: Text(t(context, "share_report_button")),
            ),
            if (!kIsWeb && Platform.isAndroid) ...[
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () => _saveToDownloads(context),
                child: Text(t(context, "save_downloads_button")),
              ),
            ],
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pushReplacement(
                MaterialPageRoute(builder: (_) => const StartReportScreen()),
              ),
              child: Text(t(context, "new_report_button")),
            ),
          ],
        ),
      ),
    );
  }
}
