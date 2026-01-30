import "dart:convert";
import "dart:io";

import "package:flutter/material.dart";
import "package:image_picker/image_picker.dart";
import "package:http/http.dart" as http;
import "package:path_provider/path_provider.dart";

const String apiBaseUrl = "http://localhost:8000";

void main() {
  runApp(const DocBotApp());
}

class DocBotApp extends StatelessWidget {
  const DocBotApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: "DocBotApp",
      theme: ThemeData(useMaterial3: true),
      home: const LoginScreen(),
    );
  }
}

class TemplateInfo {
  TemplateInfo({required this.key, required this.title});

  final String key;
  final String title;

  factory TemplateInfo.fromJson(Map<String, dynamic> json) {
    return TemplateInfo(key: json["key"], title: json["title"]);
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

class ApiClient {
  String? token;

  Future<String> login(String phone, String password) async {
    final resp = await http.post(
      Uri.parse("$apiBaseUrl/auth/login"),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({"phone": phone, "password": password}),
    );
    if (resp.statusCode != 200) {
      throw Exception(resp.body);
    }
    return jsonDecode(resp.body)["access_token"] as String;
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
    return jsonDecode(resp.body)["access_token"] as String;
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

  Future<String> addItem(String description, String notes) async {
    final resp = await http.post(
      Uri.parse("$apiBaseUrl/reports/item"),
      headers: _headers(),
      body: jsonEncode({"description": description, "notes": notes}),
    );
    if (resp.statusCode != 200) {
      throw Exception(resp.body);
    }
    return jsonDecode(resp.body)["item_id"] as String;
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
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
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
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
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
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
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

  Future<String> finalizeAndSave() async {
    final resp = await http.post(
      Uri.parse("$apiBaseUrl/reports/finalize"),
      headers: _headers(json: false),
    );
    if (resp.statusCode != 200) {
      throw Exception(resp.body);
    }
    final dir = await getApplicationDocumentsDirectory();
    final filename = "Report_${DateTime.now().millisecondsSinceEpoch}.docx";
    final file = File("${dir.path}/$filename");
    await file.writeAsBytes(resp.bodyBytes);
    return file.path;
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

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final phoneController = TextEditingController();
  final passwordController = TextEditingController();
  String? error;
  bool loading = false;

  Future<void> _auth({required bool register}) async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final phone = phoneController.text.trim();
      final password = passwordController.text;
      final token = register ? await api.register(phone, password) : await api.login(phone, password);
      api.token = token;
      if (mounted) {
        Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const StartReportScreen()));
      }
    } catch (e) {
      setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Login")),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(controller: phoneController, decoration: const InputDecoration(labelText: "Phone")),
            TextField(
              controller: passwordController,
              decoration: const InputDecoration(labelText: "Password"),
              obscureText: true,
            ),
            const SizedBox(height: 16),
            if (error != null) Text(error!, style: const TextStyle(color: Colors.red)),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: loading ? null : () => _auth(register: false),
                    child: const Text("Login"),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton(
                    onPressed: loading ? null : () => _auth(register: true),
                    child: const Text("Register"),
                  ),
                ),
              ],
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
  bool loading = false;

  @override
  void initState() {
    super.initState();
    _loadTemplates();
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

  Future<void> _start() async {
    try {
      if (selectedTemplateKey == null) {
        setState(() => error = "No template selected");
        return;
      }
      await api.startReport(locationController.text.trim(), selectedTemplateKey!);
      if (mounted) {
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ContactsScreen()));
      }
    } catch (e) {
      setState(() => error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Start Report")),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(controller: locationController, decoration: const InputDecoration(labelText: "Location")),
            const SizedBox(height: 12),
            if (templates.isNotEmpty)
              DropdownButtonFormField<String>(
                value: selectedTemplateKey,
                decoration: const InputDecoration(labelText: "Template"),
                items: templates
                    .map((t) => DropdownMenuItem(value: t.key, child: Text(t.title)))
                    .toList(),
                onChanged: (value) => setState(() => selectedTemplateKey = value),
              ),
            const SizedBox(height: 16),
            if (error != null) Text(error!, style: const TextStyle(color: Colors.red)),
            ElevatedButton(onPressed: _start, child: const Text("Start")),
          ],
        ),
      ),
    );
  }
}

class ContactsScreen extends StatefulWidget {
  const ContactsScreen({super.key});

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

  @override
  void initState() {
    super.initState();
    _loadContacts();
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

  Future<void> _addContact() async {
    try {
      final name = nameController.text.trim();
      final email = emailController.text.trim();
      if (name.isEmpty || email.isEmpty) {
        setState(() => error = "Name and email required");
        return;
      }
      final contact = await api.addContact(name: name, email: email);
      setState(() {
        contacts.add(contact);
        nameController.clear();
        emailController.clear();
      });
    } catch (e) {
      setState(() => error = e.toString());
    }
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
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AddItemScreen()));
      }
    } catch (e) {
      setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Contacts")),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            if (error != null) Text(error!, style: const TextStyle(color: Colors.red)),
            TextField(controller: nameController, decoration: const InputDecoration(labelText: "Name")),
            TextField(controller: emailController, decoration: const InputDecoration(labelText: "Email")),
            const SizedBox(height: 8),
            Row(
              children: [
                ElevatedButton(onPressed: _addContact, child: const Text("Add Contact")),
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
                                  title: const Text("Attendee"),
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
                                  title: const Text("Recipient"),
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
              child: const Text("Continue"),
            ),
          ],
        ),
      ),
    );
  }
}

class AddItemScreen extends StatefulWidget {
  const AddItemScreen({super.key});

  @override
  State<AddItemScreen> createState() => _AddItemScreenState();
}

class _AddItemScreenState extends State<AddItemScreen> {
  final descriptionController = TextEditingController();
  final notesController = TextEditingController();
  File? photo;
  String? currentItemId;
  String? error;

  Future<void> _addItem() async {
    try {
      final id = await api.addItem(
        descriptionController.text.trim(),
        notesController.text.trim(),
      );
      setState(() {
        currentItemId = id;
        descriptionController.clear();
        notesController.clear();
      });
    } catch (e) {
      setState(() => error = e.toString());
    }
  }

  Future<void> _takePhoto() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.camera);
    if (picked != null) {
      setState(() => photo = File(picked.path));
    }
  }

  Future<void> _uploadPhoto() async {
    if (photo == null) return;
    try {
      await api.uploadPhoto(photo!, itemId: currentItemId);
      setState(() => photo = null);
    } catch (e) {
      setState(() => error = e.toString());
    }
  }

  Future<void> _finalize() async {
    try {
      final path = await api.finalizeAndSave();
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => DoneScreen(filePath: path)),
        );
      }
    } catch (e) {
      setState(() => error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Add Item")),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(controller: descriptionController, decoration: const InputDecoration(labelText: "Description")),
            TextField(controller: notesController, decoration: const InputDecoration(labelText: "Notes")),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: ElevatedButton(onPressed: _takePhoto, child: const Text("Take Photo"))),
                const SizedBox(width: 12),
                Expanded(child: OutlinedButton(onPressed: _uploadPhoto, child: const Text("Upload Photo"))),
              ],
            ),
            const SizedBox(height: 12),
            ElevatedButton(onPressed: _addItem, child: const Text("Add Item")),
            const Spacer(),
            if (error != null) Text(error!, style: const TextStyle(color: Colors.red)),
            ElevatedButton(onPressed: _finalize, child: const Text("Generate Word Report")),
          ],
        ),
      ),
    );
  }
}

class DoneScreen extends StatelessWidget {
  const DoneScreen({super.key, required this.filePath});

  final String filePath;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Done")),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("Report generated."),
            const SizedBox(height: 8),
            Text(filePath, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pushReplacement(
                MaterialPageRoute(builder: (_) => const StartReportScreen()),
              ),
              child: const Text("New Report"),
            ),
          ],
        ),
      ),
    );
  }
}
