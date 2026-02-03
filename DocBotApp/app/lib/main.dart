import "dart:async";
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
import "package:record/record.dart";
import "package:photo_manager/photo_manager.dart";
import "package:in_app_update/in_app_update.dart";
import "package:package_info_plus/package_info_plus.dart";
import "package:flutter/services.dart";
import "package:flutter_secure_storage/flutter_secure_storage.dart";
import "package:crypto/crypto.dart";
import "package:geolocator/geolocator.dart";
import "package:geocoding/geocoding.dart";
import "package:image_painter/image_painter.dart";
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
final ValueNotifier<String?> selectedLogoPath = ValueNotifier(null);
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
    int deletedCount = 0;
    
    // 1. Clear photo backups
    final backupDir = Directory("${dir.path}/photo_backups");
    if (await backupDir.exists()) {
      await backupDir.delete(recursive: true);
      await backupDir.create();
    }
    
    // 2. Clear temp media and report files
    final list = dir.listSync();
    for (final item in list) {
      if (item is File) {
        final name = item.uri.pathSegments.last.toLowerCase();
        // Delete temp files, reports (pdf/docx), and recordings
        if (name.startsWith("res_timestamp") ||
            name.endsWith(".pdf") ||
            name.endsWith(".docx") ||
            name.startsWith("report_") ||
            name.endsWith(".m4a") ||
            name.endsWith(".wav")) {
          await item.delete();
          deletedCount++;
        }
      }
    }
    
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("${t(context, "clean_files_success")} ($deletedCount)")),
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
        } else if (value == "profile") {
          Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ProfileScreen()));
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
          PopupMenuItem<String>(
            value: "profile",
            child: Text(t(context, "profile_title")),
          ),
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
          theme: ThemeData(
            useMaterial3: true,
            colorScheme: ColorScheme.fromSeed(
              seedColor: Colors.blue,
              brightness: Brightness.light,
            ),
          ),
          darkTheme: ThemeData(
            useMaterial3: true,
            colorScheme: ColorScheme.fromSeed(
              seedColor: Colors.blue,
              brightness: Brightness.dark,
            ),
          ),
          themeMode: ThemeMode.system,
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
    required this.projectName,
    required this.tags,
  });

  final String reportId;
  final String createdAt;
  final String location;
  final String templateKey;
  final String title;
  final String titleHe;
  final String folder;
  final String projectName;
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
      projectName: json["project_name"] ?? "",
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
    required this.projectName,
    required this.attendees,
    required this.distributionList,
  });

  final List<ReportItemData> items;
  final List<ReportPhotoData> photos;
  final String location;
  final String title;
  final String titleHe;
  final String templateKey;
  final String projectName;
  final List<String> attendees;
  final List<String> distributionList;
}

class ApiClient {
  String? token;

  dynamic _decodeJson(http.Response resp) {
    return jsonDecode(utf8.decode(resp.bodyBytes));
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
      projectName: session["project_name"]?.toString() ?? "",
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

  Future<void> deleteItem(String itemId) async {
    final resp = await http.delete(
      Uri.parse("$apiBaseUrl/reports/item/$itemId"),
      headers: _headers(),
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

  Future<void> deleteReport(String reportId) async {
    final resp = await http.delete(
      Uri.parse("$apiBaseUrl/reports/$reportId"),
      headers: _headers(),
    );
    if (resp.statusCode != 200) {
      throw Exception(resp.body);
    }
  }

  Future<void> startReport(String location, String templateKey, {String? projectName}) async {
    final resp = await http.post(
      Uri.parse("$apiBaseUrl/reports/start"),
      headers: _headers(),
      body: jsonEncode({
        "location": location,
        "template_key": templateKey,
        "project_name": projectName,
      }),
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

  Future<String> finalizeAndSave({String? filename, File? logoFile, bool pdf = false}) async {
    final endpoint = pdf ? "finalize_pdf" : "finalize";
    final req = http.MultipartRequest(
      "POST",
      Uri.parse("$apiBaseUrl/reports/$endpoint"),
    );
    req.headers.addAll(_headers(json: false));
    if (logoFile != null) {
      req.files.add(await http.MultipartFile.fromPath("logo", logoFile.path));
    }

    final streamed = await req.send();
    final resp = await http.Response.fromStream(streamed);

    if (resp.statusCode != 200) {
      throw Exception(resp.body);
    }
    final dir = await getApplicationDocumentsDirectory();
    final ext = pdf ? ".pdf" : ".docx";
    final fallback = "Report_${DateTime.now().millisecondsSinceEpoch}$ext";
    final name = (filename == null || filename.isEmpty) ? fallback : filename;
    final finalName = name.endsWith(ext) ? name : "$name$ext";
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

  /// Returns a map with: text, error_key, remaining_report_seconds, remaining_total_seconds
  Future<Map<String, dynamic>> transcribeAudio(File file, {String? language}) async {
    final req = http.MultipartRequest(
      "POST",
      Uri.parse("$apiBaseUrl/reports/transcribe"),
    );
    req.headers.addAll(_headers(json: false));
    if (language != null && language.isNotEmpty) {
      req.fields["language"] = language;
    }
    req.files.add(await http.MultipartFile.fromPath("file", file.path));
    final streamed = await req.send();
    final body = await streamed.stream.bytesToString();
    if (streamed.statusCode != 200) {
      throw Exception(body);
    }
    final data = jsonDecode(body) as Map<String, dynamic>;
    return {
      "text": (data["text"] ?? "").toString(),
      "error_key": (data["error_key"] ?? "").toString(),
      "remaining_report_seconds": data["remaining_report_seconds"] ?? 30,
      "remaining_total_seconds": data["remaining_total_seconds"] ?? 300,
    };
  }

  Future<Map<String, dynamic>> getMe() async {
    final resp = await http.get(Uri.parse("$apiBaseUrl/auth/me"), headers: _headers());
    if (resp.statusCode != 200) throw Exception(resp.body);
    return jsonDecode(resp.body);
  }

  Future<void> updateProfile({
    String? fullName,
    String? roleTitle,
    String? phoneContact,
    String? companyName,
    String? signaturePath,
  }) async {
    final resp = await http.put(
      Uri.parse("$apiBaseUrl/auth/profile"),
      headers: _headers(),
      body: jsonEncode({
        "full_name": fullName,
        "role_title": roleTitle,
        "phone_contact": phoneContact,
        "company_name": companyName,
        "signature_path": signaturePath,
      }),
    );
    if (resp.statusCode != 200) throw Exception(resp.body);
  }

  Future<void> uploadSignature(File file) async {
    final req = http.MultipartRequest(
      "POST",
      Uri.parse("$apiBaseUrl/auth/signature"),
    );
    req.headers.addAll(_headers(json: false));
    req.files.add(await http.MultipartFile.fromPath("file", file.path));
    final streamed = await req.send();
    if (streamed.statusCode != 200) {
      final body = await streamed.stream.bytesToString();
      throw Exception(body);
    }
  }

  Future<void> uploadProfileLogo(File file) async {
    final req = http.MultipartRequest(
      "POST",
      Uri.parse("$apiBaseUrl/auth/logo"),
    );
    req.headers.addAll(_headers(json: false));
    req.files.add(await http.MultipartFile.fromPath("file", file.path));
    final streamed = await req.send();
    if (streamed.statusCode != 200) {
      final body = await streamed.stream.bytesToString();
      throw Exception(body);
    }
  }

  String getSignatureUrl() {
    return "$apiBaseUrl/auth/signature";
  }

  String getProfileLogoUrl() {
    return "$apiBaseUrl/auth/logo";
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
            const Spacer(),
            Text(
              "API: $apiBaseUrl",
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _testConnection,
              icon: const Icon(Icons.network_check, size: 16),
              label: const Text("Test Connection", style: TextStyle(fontSize: 12)),
            ),
            if (connectionStatus != null)
              Padding(
                padding: const EdgeInsets.only(top: 4, bottom: 8),
                child: Text(connectionStatus!, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: connectionStatus!.startsWith("OK") ? Colors.green : Colors.red)),
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
  final projectController = TextEditingController();
  String? error;
  List<TemplateInfo> templates = [];
  String? selectedTemplateKey;
  List<String> recentLocations = [];
  List<String> locationHistory = [];
  bool loading = false;

  List<String> logos = [];

  @override
  void initState() {
    super.initState();
    _loadTemplates();
    _loadLocations();
    _loadLocationHistory();
    _loadLogos();
  }

  Future<void> _loadLogos() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList("user_logos") ?? [];
    final selected = prefs.getString("selected_logo");
    if (mounted) {
      setState(() => logos = list);
      selectedLogoPath.value = selected;
    }
  }

  Future<void> _saveLogos() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList("user_logos", logos);
    if (selectedLogoPath.value != null) {
      await prefs.setString("selected_logo", selectedLogoPath.value!);
    } else {
      await prefs.remove("selected_logo");
    }
  }

  Future<void> _pickLogo() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked != null) {
      setState(() {
        if (!logos.contains(picked.path)) {
          logos.add(picked.path);
        }
        selectedLogoPath.value = picked.path;
      });
      await _saveLogos();
    }
  }

  Future<void> _detectLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() => error = t(context, "location_not_found"));
        return;
      }
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          setState(() => error = t(context, "location_permission_denied"));
          return;
        }
      }
      if (permission == LocationPermission.deniedForever) {
        setState(() => error = t(context, "location_permission_denied"));
        return;
      }

      final pos = await Geolocator.getCurrentPosition();
      final placemarks = await placemarkFromCoordinates(pos.latitude, pos.longitude);
      if (placemarks.isNotEmpty) {
        final p = placemarks.first;
        final addr = "${p.street}, ${p.locality}, ${p.country}";
        setState(() => locationController.text = addr);
      }
    } catch (e) {
      setState(() => error = e.toString());
    }
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
        // Ask user if they want to continue existing report or start fresh
        final choice = await showDialog<String>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(t(context, "existing_report_title")),
            content: Text(t(context, "existing_report_body")),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop("new"),
                child: Text(t(context, "start_new_button")),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop("continue"),
                child: Text(t(context, "continue_existing_button")),
              ),
            ],
          ),
        );
        
        if (choice == "continue" && mounted) {
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
          return;
        } else if (choice == "new") {
          // Cancel existing and start new
          await api.cancelReport();
        } else {
          return; // User dismissed dialog
        }
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
      await api.startReport(
        locationController.text.trim(),
        selectedTemplateKey!,
        projectName: projectController.text.trim(),
      );
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
                  decoration: InputDecoration(
                    labelText: t(context, "location_label"),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.my_location),
                      tooltip: t(context, "detect_location_tooltip"),
                      onPressed: () async {
                        await _detectLocation();
                        controller.text = locationController.text;
                      },
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: projectController,
              decoration: InputDecoration(
                labelText: t(context, "project_name_label"),
                hintText: t(context, "project_name_hint"),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            ExpansionTile(
              title: Text(t(context, "logo_selector_title")),
              subtitle: ValueListenableBuilder<String?>(
                valueListenable: selectedLogoPath,
                builder: (context, path, _) => path != null 
                  ? Text(path.split("/").last)
                  : Text(t(context, "no_logos_yet")),
              ),
              children: [
                if (logos.isNotEmpty)
                  SizedBox(
                    height: 100,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: logos.length,
                      itemBuilder: (context, index) {
                        final path = logos[index];
                        return ValueListenableBuilder<String?>(
                          valueListenable: selectedLogoPath,
                          builder: (context, selectedPath, _) {
                            final isSelected = selectedPath == path;
                            return GestureDetector(
                              onTap: () {
                                selectedLogoPath.value = isSelected ? null : path;
                                _saveLogos();
                              },
                              child: Container(
                                margin: const EdgeInsets.symmetric(horizontal: 4),
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: isSelected ? Colors.blue : Colors.grey,
                                    width: isSelected ? 3 : 1,
                                  ),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Stack(
                                  children: [
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(5),
                                      child: Image.file(File(path), width: 80, height: 80, fit: BoxFit.cover),
                                    ),
                                    if (isSelected)
                                      const Positioned(
                                        right: 2,
                                        top: 2,
                                        child: Icon(Icons.check_circle, color: Colors.blue, size: 20),
                                      ),
                                  ],
                                ),
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),
                ListTile(
                  leading: const Icon(Icons.add_photo_alternate),
                  title: Text(t(context, "pick_logo_button")),
                  onTap: _pickLogo,
                ),
              ],
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
  List<ReportSummary> allReports = [];
  List<ReportSummary> filteredReports = [];
  bool loading = true;
  String? error;
  String searchQuery = "";
  String groupingMode = "project"; // "none", "project", "folder"

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final list = await api.listRecentReports();
      if (mounted) {
        setState(() {
          allReports = list;
          filteredReports = list;
          loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          error = e.toString();
          loading = false;
        });
      }
    }
  }

  void _search(String query) {
    setState(() {
      searchQuery = query;
      if (query.isEmpty) {
        filteredReports = allReports;
      } else {
        final q = query.toLowerCase();
        filteredReports = allReports.where((r) {
          return r.location.toLowerCase().contains(q) ||
              r.projectName.toLowerCase().contains(q) ||
              r.title.toLowerCase().contains(q) ||
              r.titleHe.toLowerCase().contains(q);
        }).toList();
      }
    });
  }

  Map<String, List<ReportSummary>> _getGroupedReports() {
    final grouped = <String, List<ReportSummary>>{};
    for (final r in filteredReports) {
      String key;
      if (groupingMode == "folder") {
        key = r.folder.isEmpty ? t(context, "no_folders_yet") : r.folder;
      } else {
        key = r.projectName.isEmpty ? t(context, "no_projects_yet") : r.projectName;
      }
      grouped.putIfAbsent(key, () => []).add(r);
    }
    return grouped;
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
              templateTitle: appLocale.value.languageCode == "he" ? report.titleHe : report.title,
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
    final existingFolders = allReports
        .map((r) => r.folder)
        .where((f) => f.isNotEmpty)
        .toSet()
        .toList();

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t(context, "organize_report_button")),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Autocomplete<String>(
              initialValue: TextEditingValue(text: report.folder),
              optionsBuilder: (value) {
                if (value.text.isEmpty) return existingFolders;
                return existingFolders.where((f) => f.toLowerCase().contains(value.text.toLowerCase()));
              },
              onSelected: (val) => folderController.text = val,
              fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
                controller.addListener(() => folderController.text = controller.text);
                return TextField(
                  controller: controller,
                  focusNode: focusNode,
                  textDirection: _textDirection(context),
                  textAlign: _textAlign(context),
                  decoration: InputDecoration(labelText: t(context, "folder_label")),
                );
              },
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
    await _load();
  }

  Future<void> _deleteReport(ReportSummary report) async {
    final title = appLocale.value.languageCode == "he" ? report.titleHe : report.title;
    final proceed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t(context, "delete_report_title")),
        content: Text("${t(context, "delete_report_body")}\n\n$title\n${report.location}"),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(t(context, "cancel_button")),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(t(context, "delete_button")),
          ),
        ],
      ),
    );
    if (proceed != true) return;
    
    try {
      await api.deleteReport(report.reportId);
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error: $e")),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return Scaffold(appBar: AppBar(), body: const Center(child: CircularProgressIndicator()));

    final grouped = _getGroupedReports();
    final groupKeys = grouped.keys.toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(t(context, "recent_reports_title")),
        actions: [
          PopupMenuButton<String>(
            icon: Icon(groupingMode == "none"
                ? Icons.view_list
                : groupingMode == "folder"
                    ? Icons.folder
                    : Icons.view_agenda),
            onSelected: (value) => setState(() => groupingMode = value),
            itemBuilder: (context) => [
              PopupMenuItem(value: "none", child: Text(t(context, "open_report_button"))),
              PopupMenuItem(value: "project", child: Text(t(context, "group_by_project"))),
              PopupMenuItem(value: "folder", child: Text(t(context, "group_by_folder"))),
            ],
          ),
          ...appBarActions(context, showLogout: true),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              onChanged: _search,
              decoration: InputDecoration(
                hintText: t(context, "search_reports_hint"),
                prefixIcon: const Icon(Icons.search),
                border: const OutlineInputBorder(),
              ),
            ),
          ),
          Expanded(
            child: error != null
                ? Center(child: Text(error!))
                : groupingMode != "none"
                    ? ListView.builder(
                        itemCount: groupKeys.length,
                        itemBuilder: (context, i) {
                          final key = groupKeys[i];
                          final reports = grouped[key]!;
                          return ExpansionTile(
                            initiallyExpanded: true,
                            title: Text(key, style: const TextStyle(fontWeight: FontWeight.bold)),
                            subtitle: Text("${reports.length} ${t(context, "recent_reports_title")}"),
                            children: reports.map((r) => _buildReportTile(r)).toList(),
                          );
                        },
                      )
                    : ListView.builder(
                        itemCount: filteredReports.length,
                        itemBuilder: (context, i) => _buildReportTile(filteredReports[i]),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildReportTile(ReportSummary report) {
    final subtitleParts = <String>[
      report.createdAt,
      if (report.location.isNotEmpty) report.location,
      if (report.folder.isNotEmpty) "📁 ${report.folder}",
      if (report.tags.isNotEmpty) "🏷 ${report.tags.join(", ")}",
      if (report.projectName.isNotEmpty) "🏗 ${report.projectName}",
    ];
    return Card(
      child: ListTile(
        title: Text(appLocale.value.languageCode == "he" ? report.titleHe : report.title),
        subtitle: Text(subtitleParts.join(" • ")),
        trailing: Wrap(
          spacing: 4,
          children: [
            IconButton(
              icon: const Icon(Icons.edit, size: 20),
              onPressed: loading ? null : () => _openForEdit(report),
              tooltip: t(context, "edit_report_button"),
            ),
            IconButton(
              icon: const Icon(Icons.folder, size: 20),
              onPressed: loading ? null : () => _organize(report),
              tooltip: t(context, "organize_report_button"),
            ),
            IconButton(
              icon: Icon(Icons.delete_outline, size: 20, color: Colors.red[400]),
              onPressed: loading ? null : () => _deleteReport(report),
              tooltip: t(context, "delete_report_title"),
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
  final AudioRecorder audioRecorder = AudioRecorder();
  StreamSubscription<Amplitude>? _ampSub;
  bool isRecording = false;
  String lastTranscript = "";
  double soundLevel = 0.0;
  String? recordingItemId;
  String? recordingField;
  bool _usingLocalStt = false;
  List<String> descriptionHistory = [];
  List<String> notesHistory = [];
  List<ReportItemData> existingItems = [];
  String? editingItemId;
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
    _ampSub?.cancel();
    audioRecorder.dispose();
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

  String _resolveTranscriptionLanguage() {
    final lang = Localizations.localeOf(context).languageCode.toLowerCase();
    if (lang == "iw") return "he";
    if (lang == "he") return "he";
    return lang;
  }

  bool _localeMatchesLanguage(String localeId, String lang) {
    final id = localeId.toLowerCase();
    if (lang == "he") {
      return id.startsWith("he") || id.startsWith("iw");
    }
    return id.startsWith(lang);
  }

  Future<bool> _hasLocalSttLanguage(String lang) async {
    try {
      final locales = await speech.locales();
      return locales.any((l) => _localeMatchesLanguage(l.localeId, lang));
    } catch (e) {
      return false;
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

  Future<String?> _startTranscriptionRecording() async {
    if (kIsWeb) return null;
    try {
      final dir = await getApplicationDocumentsDirectory();
      final recordingsDir = Directory("${dir.path}/transcriptions");
      if (!await recordingsDir.exists()) {
        await recordingsDir.create(recursive: true);
      }
      final filename = "speech_${DateTime.now().millisecondsSinceEpoch}.m4a";
      final path = "${recordingsDir.path}/$filename";

      final hasPerm = await audioRecorder.hasPermission();
      if (!hasPerm) return null;

      await audioRecorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          sampleRate: 16000,
          bitRate: 64000,
          numChannels: 1,
        ),
        path: path,
      );

      await _ampSub?.cancel();
      _ampSub = audioRecorder
          .onAmplitudeChanged(const Duration(milliseconds: 200))
          .listen((amp) {
        if (mounted) setState(() => soundLevel = amp.current);
      });

      return path;
    } catch (_) {
      return null;
    }
  }

  Future<String?> _stopTranscriptionRecording() async {
    if (kIsWeb) return null;
    try {
      final path = await audioRecorder.stop();
      await _ampSub?.cancel();
      _ampSub = null;
      if (mounted) setState(() => soundLevel = 0.0);
      return path;
    } catch (_) {
      return null;
    }
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
                return GestureDetector(
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => FullScreenImageViewer(
                          imageUrl: url,
                          headers: headers,
                        ),
                      ),
                    );
                  },
                  child: Hero(
                    tag: photo.id,
                    child: ClipRRect(
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
                    ),
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

  Future<bool> _ensureActiveItemForMedia() async {
    if (activeItemId != null) return true;
    
    // If there's text in the controllers, save it first before creating the item
    final descriptionTrimmed = descriptionController.text.trim();
    final notesTrimmed = notesController.text.trim();
    
    if (descriptionTrimmed.isNotEmpty || notesTrimmed.isNotEmpty) {
      // Save the text as a new item
      try {
        final id = await api.addItem(descriptionTrimmed, notesTrimmed);
        setState(() {
          currentItemId = id;
          activeItemId = id;
          editingItemId = id; // Set to the new item so "Add Item" will update, not create another
        });
        await _loadExistingItems();
        return activeItemId != null;
      } catch (e) {
        setState(() => error = e.toString());
        return false;
      }
    }
    
    // If no text, create an empty item
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
          if (mounted) {
            setState(() {
              activeItemId = null;
              currentItemId = null;
              editingItemId = null;
            });
          }
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
          activeItemId = null;
          currentItemId = null;
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

  Future<File?> _processImageWithMarkup(XFile picked) async {
    final edited = await Navigator.of(context).push<File>(
      MaterialPageRoute(
        builder: (_) => ImageMarkupScreen(imageFile: File(picked.path)),
      ),
    );
    return edited;
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
    final picked = await picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 85,
      maxWidth: 1920,
    );
    if (picked != null) {
      final finalFile = await _processImageWithMarkup(picked) ?? File(picked.path);
      setState(() => photo = finalFile);
      final saved = await _savePhotoToGallery(finalFile.path);
      String? backupPath;
      if (!saved) {
        backupPath = await _backupPhotoToDevice(finalFile.path);
      }
      _cleanupTempMedia(picked.path);
      await _uploadPhotoFile(finalFile, activeItemId!, backupPath: backupPath);
    }
  }

  Future<void> _uploadPhoto() async {
    if (!await _ensureActiveItemForMedia()) {
      return;
    }
    if (error != null) {
      setState(() => error = null);
    }
    final photosOk = await _requestGalleryPermission();
    if (!photosOk) {
      setState(() => error = t(context, "permission_photos_denied"));
      return;
    }
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
      maxWidth: 1920,
    );
    if (picked == null) return;
    final finalFile = await _processImageWithMarkup(picked) ?? File(picked.path);
    final saved = await _savePhotoToGallery(finalFile.path);
    String? backupPath;
    if (!saved) {
      backupPath = await _backupPhotoToDevice(finalFile.path);
    }
    _cleanupTempMedia(picked.path);
    await _uploadPhotoFile(finalFile, activeItemId!, backupPath: backupPath);
  }

  Future<bool> _requestGalleryPermission() async {
    if (kIsWeb) return true;
    if (Platform.isAndroid) {
      final photos = await Permission.photos.request();
      if (photos.isGranted) return true;
      final storage = await Permission.storage.request();
      return storage.isGranted;
    }
    final photos = await Permission.photos.request();
    return photos.isGranted;
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

  void _hideLoading() {
    if (mounted) {
      Navigator.of(context, rootNavigator: true).pop();
    }
  }

  void _showLoading(String message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => WillPopScope(
        onWillPop: () async => false,
        child: AlertDialog(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(message),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _finalize({bool pdf = false}) async {
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
      _showLoading(t(context, pdf ? "generating_pdf_loading" : "generating_report_loading"));
      File? logo;
      if (selectedLogoPath.value != null) {
        logo = File(selectedLogoPath.value!);
      }
      final path = await api.finalizeAndSave(filename: filename, logoFile: logo, pdf: pdf);
      _hideLoading();
      if (mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => DoneScreen(filePath: path)),
        );
      }
    } catch (e) {
      if (mounted) _hideLoading();
      setState(() => error = e.toString());
    }
  }

  Future<void> _deleteItem(String itemId) async {
    final item = existingItems.firstWhere((i) => i.id == itemId, orElse: () => ReportItemData(id: "", number: "", description: "", notes: ""));
    final label = item.description.isNotEmpty ? item.description : (item.notes.isNotEmpty ? item.notes : t(context, "item") + " ${item.number}");
    
    final proceed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t(context, "delete_item_title")),
        content: Text("${t(context, "delete_item_body")}\n\n$label"),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(t(context, "cancel_button")),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(t(context, "delete_button")),
          ),
        ],
      ),
    );
    if (proceed != true) return;
    
    try {
      await api.deleteItem(itemId);
      if (mounted) {
        setState(() {
          if (activeItemId == itemId) {
            activeItemId = null;
            currentItemId = null;
            editingItemId = null;
            descriptionController.clear();
            notesController.clear();
          }
        });
        await _loadExistingItems();
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
        if (error != null) setState(() => error = null);
        final micOk = await Permission.microphone.request();
        if (!micOk.isGranted) {
          setState(() => error = t(context, "transcription_error"));
          return;
        }

        final lang = _resolveTranscriptionLanguage();
        bool localAvailable = false;
        try {
          localAvailable = await speech.initialize(
            onStatus: (status) {
              debugPrint("STT Status: $status");
            },
            onError: (err) {
              debugPrint("STT Error: ${err.errorMsg}");
              if (mounted) {
                setState(() => error = t(context, "transcription_error"));
              }
            },
            debugLogging: true,
          );
        } catch (_) {
          localAvailable = false;
        }

        if (localAvailable && await _hasLocalSttLanguage(lang)) {
          setState(() {
            isRecording = true;
            recordingItemId = targetItemId;
            recordingField = targetField;
            _usingLocalStt = true;
            lastTranscript = "";
          });
          await speech.listen(
            localeId: lang,
            onResult: (result) {
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
          final path = await _startTranscriptionRecording();
          if (path == null) {
            setState(() {
              isRecording = false;
              error = t(context, "transcription_error");
            });
            return;
          }
          setState(() {
            isRecording = true;
            recordingItemId = targetItemId;
            recordingField = targetField;
            _usingLocalStt = false;
          });
        }
      } else {
        final target = recordingItemId;
        final field = recordingField;
        if (mounted) {
          setState(() {
            isRecording = false;
            recordingItemId = null;
            recordingField = null;
          });
        }
        if (_usingLocalStt) {
          await speech.stop();
          _usingLocalStt = false;
          if (target != null && lastTranscript.isNotEmpty) {
            await _applyTranscriptToItem(target, lastTranscript);
          }
          if (mounted) setState(() => soundLevel = 0.0);
        } else {
          final path = await _stopTranscriptionRecording();
          if (path == null) {
            setState(() => error = t(context, "transcription_error"));
            return;
          }
          final language = _resolveTranscriptionLanguage();
          _showLoading(t(context, "transcribing_loading"));
          final result = await api.transcribeAudio(File(path), language: language);
          _hideLoading();
          try {
            await File(path).delete();
          } catch (_) {}
          
          final errorKey = result["error_key"] as String? ?? "";
          if (errorKey.isNotEmpty) {
            setState(() => error = t(context, errorKey));
            return;
          }
          
          final transcript = result["text"] as String? ?? "";
          if (transcript.trim().isEmpty) {
            setState(() => error = t(context, "transcription_error"));
            return;
          }
          setState(() => lastTranscript = transcript);
          if (target != null) {
            await _applyTranscriptToItem(target, transcript);
          } else if (field == "description") {
            final current = descriptionController.text.trim();
            final combined = current.isEmpty ? transcript : "$current\n$transcript";
            descriptionController.text = combined;
            descriptionController.selection = TextSelection.fromPosition(
              TextPosition(offset: descriptionController.text.length),
            );
          } else {
            final current = notesController.text.trim();
            final combined = current.isEmpty ? transcript : "$current\n$transcript";
            notesController.text = combined;
            notesController.selection = TextSelection.fromPosition(
              TextPosition(offset: notesController.text.length),
            );
          }
        }
      }
    } catch (e) {
      debugPrint("Toggle recording error: $e");
      if (mounted) {
        setState(() {
          isRecording = false;
          error = t(context, "transcription_error");
        });
      }
    }
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

  @override
  Widget build(BuildContext context) {
    final visibleItems = existingItems.where(_itemHasContent).toList();
    final allPhotos = itemPhotos.values.expand((e) => e).toList();
    final headers = api.token != null ? {"Authorization": "Bearer ${api.token}"} : <String, String>{};

    return Scaffold(
      appBar: AppBar(
        title: Text(t(context, "add_item_title")),
        actions: [
          if (allPhotos.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.photo_library),
              tooltip: t(context, "gallery_title"),
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ReportGalleryScreen(
                      photos: allPhotos,
                      headers: headers,
                    ),
                  ),
                );
              },
            ),
          ...appBarActions(
            context,
            showLogout: true,
            showCancelReport: true,
            onSelected: (value) {
              if (value == "cancel_report") {
                _cancelReport();
              }
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (visibleItems.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey[300]!),
                borderRadius: BorderRadius.circular(8),
              ),
              constraints: const BoxConstraints(maxHeight: 200),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: visibleItems.length,
                padding: EdgeInsets.zero,
                itemBuilder: (context, index) {
                  final item = visibleItems[index];
                  return ListTile(
                    dense: true,
                    title: Text("${item.number}. ${item.description}"),
                    subtitle: Text(item.notes, maxLines: 1, overflow: TextOverflow.ellipsis),
                    selected: item.id == activeItemId,
                    selectedTileColor: Theme.of(context).colorScheme.primary.withOpacity(0.08),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline, size: 20),
                      color: Colors.red[400],
                      tooltip: t(context, "delete_item_title"),
                      onPressed: () => _deleteItem(item.id),
                    ),
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
                      value: (soundLevel + 2) / 15,
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
                      value: (soundLevel + 2) / 15,
                      backgroundColor: Colors.grey[200],
                      valueColor: AlwaysStoppedAnimation<Color>(Theme.of(context).primaryColor),
                    ),
                  ),
                ),
            ],
          ),
          _buildAttachments(),
          const SizedBox(height: 12),
          if (isRecording)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                t(context, _usingLocalStt ? "transcription_mode_local" : "transcription_mode_server"),
                style: TextStyle(color: Theme.of(context).colorScheme.secondary),
              ),
            ),
          const SizedBox(height: 12),
          ElevatedButton(onPressed: _addItem, child: Text(t(context, "add_item_button"))),
          const SizedBox(height: 12),
          if (error != null) Text(error!, style: const TextStyle(color: Colors.red)),
          const SizedBox(height: 8),
          ElevatedButton(
            onPressed: () => _finalize(pdf: true),
            child: Text(t(context, "generate_pdf_button")),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: () => _finalize(pdf: false),
            child: Text(t(context, "generate_docx_button")),
          ),
          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 8),
          TextButton.icon(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: _cancelReport,
            icon: const Icon(Icons.cancel_outlined),
            label: Text(t(context, "cancel_report_button")),
          ),
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

  void _goToStart(BuildContext context) {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const StartReportScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        _goToStart(context);
        return false;
      },
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
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
                onPressed: () => _goToStart(context),
                child: Text(t(context, "new_report_button")),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class FullScreenImageViewer extends StatelessWidget {
  const FullScreenImageViewer({
    super.key,
    required this.imageUrl,
    this.headers,
  });

  final String imageUrl;
  final Map<String, String>? headers;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Center(
        child: InteractiveViewer(
          minScale: 0.5,
          maxScale: 4.0,
          child: Image.network(
            imageUrl,
            headers: headers,
            fit: BoxFit.contain,
            loadingBuilder: (context, child, loadingProgress) {
              if (loadingProgress == null) return child;
              return const Center(child: CircularProgressIndicator());
            },
            errorBuilder: (context, error, stackTrace) {
              return const Center(
                child: Icon(Icons.broken_image, color: Colors.white, size: 48),
              );
            },
          ),
        ),
      ),
    );
  }
}

class ImageMarkupScreen extends StatefulWidget {
  const ImageMarkupScreen({super.key, required this.imageFile});
  final File imageFile;

  @override
  State<ImageMarkupScreen> createState() => _ImageMarkupScreenState();
}

class _ImageMarkupScreenState extends State<ImageMarkupScreen> {
  late ImagePainterController _controller;

  @override
  void initState() {
    super.initState();
    _controller = ImagePainterController(
      color: Colors.red,
      mode: PaintMode.freeStyle,
      strokeWidth: 4.0,
    );
  }

  Future<void> _save() async {
    final bytes = await _controller.exportImage();
    if (bytes != null) {
      final dir = await getTemporaryDirectory();
      final path = "${dir.path}/markup_${DateTime.now().millisecondsSinceEpoch}.png";
      final file = File(path);
      await file.writeAsBytes(bytes);
      if (mounted) Navigator.of(context).pop(file);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(t(context, "save_markup")),
        actions: [
          IconButton(onPressed: _save, icon: const Icon(Icons.check)),
        ],
      ),
      body: ImagePainter.file(
        widget.imageFile,
        controller: _controller,
        scalable: true,
      ),
    );
  }
}

class ReportGalleryScreen extends StatelessWidget {
  const ReportGalleryScreen({
    super.key,
    required this.photos,
    required this.headers,
  });

  final List<ReportPhotoData> photos;
  final Map<String, String> headers;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(t(context, "gallery_title"))),
      body: GridView.builder(
        padding: const EdgeInsets.all(8),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
        ),
        itemCount: photos.length,
        itemBuilder: (context, index) {
          final photo = photos[index];
          final url = "$apiBaseUrl/reports/photo/${photo.id}";
          return GestureDetector(
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => FullScreenImageViewer(
                    imageUrl: url,
                    headers: headers,
                  ),
                ),
              );
            },
            child: Hero(
              tag: photo.id,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(
                  url,
                  headers: headers,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const Icon(Icons.broken_image),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final nameController = TextEditingController();
  final roleController = TextEditingController();
  final phoneController = TextEditingController();
  final companyController = TextEditingController();
  bool loading = true;
  String? error;
  String? signaturePath;
  String? profileLogoPath;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    try {
      final data = await api.getMe();
      if (mounted) {
        setState(() {
          nameController.text = data["full_name"] ?? "";
          roleController.text = data["role_title"] ?? "";
          phoneController.text = data["phone_contact"] ?? "";
          companyController.text = data["company_name"] ?? "";
          signaturePath = data["signature_path"];
          profileLogoPath = data["logo_path"];
          loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    }
  }

  Future<void> _pickProfileLogo() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked != null) {
      setState(() => loading = true);
      try {
        await api.uploadProfileLogo(File(picked.path));
        await _loadProfile();
      } catch (e) {
        if (mounted) setState(() => error = e.toString());
      } finally {
        if (mounted) setState(() => loading = false);
      }
    }
  }

  Future<void> _pickSignature() async {
    final controller = ImagePainterController(
      color: Colors.black,
      strokeWidth: 4,
      mode: PaintMode.freeStyle,
    );

    final signature = await showDialog<Uint8List?>(
      context: context,
      builder: (context) => Scaffold(
        appBar: AppBar(
          title: Text(t(context, "sign_button")),
          actions: [
            IconButton(
              icon: const Icon(Icons.check),
              onPressed: () async {
                final image = await controller.exportImage();
                if (mounted) Navigator.of(context).pop(image);
              },
            ),
          ],
        ),
        body: Container(
          color: Colors.white,
          child: ImagePainter.signature(
            controller: controller,
            height: double.infinity,
            width: double.infinity,
          ),
        ),
      ),
    );

    if (signature != null) {
      setState(() => loading = true);
      try {
        final dir = await getTemporaryDirectory();
        final file = File("${dir.path}/sig_${DateTime.now().millisecondsSinceEpoch}.png");
        await file.writeAsBytes(signature);
        await api.uploadSignature(file);
        await _loadProfile();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(t(context, "signature_saved_success"))),
          );
        }
      } catch (e) {
        if (mounted) setState(() => error = e.toString());
      } finally {
        if (mounted) setState(() => loading = false);
      }
    }
  }

  Future<void> _save() async {
    setState(() => loading = true);
    try {
      await api.updateProfile(
        fullName: nameController.text.trim(),
        roleTitle: roleController.text.trim(),
        phoneContact: phoneController.text.trim(),
        companyName: companyController.text.trim(),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(t(context, "profile_saved_success"))),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) setState(() {
        error = e.toString();
        loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(t(context, "profile_title"))),
      body: loading 
        ? const Center(child: CircularProgressIndicator())
        : ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (error != null) Text(error!, style: const TextStyle(color: Colors.red)),
              TextField(
                controller: nameController,
                decoration: InputDecoration(labelText: t(context, "full_name_label")),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: roleController,
                decoration: InputDecoration(labelText: t(context, "role_title_label")),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: phoneController,
                decoration: InputDecoration(labelText: t(context, "phone_contact_label")),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: companyController,
                decoration: InputDecoration(labelText: t(context, "company_name_label")),
              ),
              const SizedBox(height: 24),
              Text(t(context, "logo_selector_title"), style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              if (profileLogoPath != null)
                Container(
                  height: 100,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Image.network(
                    api.getProfileLogoUrl(),
                    headers: api._headers(),
                    key: ValueKey(profileLogoPath),
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const Icon(Icons.business, size: 40, color: Colors.grey),
                  ),
                )
              else
                Container(
                  height: 100,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey, style: BorderStyle.solid),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Center(child: Icon(Icons.business, size: 40, color: Colors.grey)),
                ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _pickProfileLogo,
                icon: const Icon(Icons.add_photo_alternate),
                label: Text(t(context, "pick_logo_button")),
              ),
              const SizedBox(height: 24),
              Text(t(context, "signature_label"), style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              if (signaturePath != null)
                Container(
                  height: 100,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Image.network(
                    api.getSignatureUrl(),
                    headers: api._headers(),
                    // Cache buster to ensure update shows immediately
                    key: ValueKey(signaturePath),
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const Icon(Icons.gesture, size: 40, color: Colors.grey),
                  ),
                )
              else
                Container(
                  height: 100,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey, style: BorderStyle.solid),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Center(child: Icon(Icons.gesture, size: 40, color: Colors.grey)),
                ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _pickSignature,
                icon: const Icon(Icons.edit),
                label: Text(t(context, "sign_button")),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _save,
                child: Text(t(context, "save_profile_button")),
              ),
            ],
          ),
    );
  }
}
