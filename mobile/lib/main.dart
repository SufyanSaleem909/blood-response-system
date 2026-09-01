import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'firebase_options.dart';

const String baseUrl = "http://192.168.100.53:8000";

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const BloodApp());
}

class BloodApp extends StatelessWidget {
  const BloodApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Blood Response System',
      theme: ThemeData(colorSchemeSeed: Colors.red, useMaterial3: true),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String? userId;
  final nameCtrl = TextEditingController();
  final phoneCtrl = TextEditingController();
  String bloodType = "O-";
  final bloodTypes = ["O-", "O+", "A-", "A+", "B-", "B+", "AB-", "AB+"];
  bool isLoading = false;

  @override
  void initState() {
    super.initState();
    FirebaseMessaging.onMessage.listen((message) {
      if (message.notification != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              "${message.notification!.title}: ${message.notification!.body}",
            ),
          ),
        );
      }
    });
  }

  @override
  void dispose() {
    nameCtrl.dispose();
    phoneCtrl.dispose();
    super.dispose();
  }

  Future<Position> _getLocation() async {
    LocationPermission perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    return Geolocator.getCurrentPosition();
  }

  Future<String?> _getFcmToken() async {
    try {
      await FirebaseMessaging.instance.requestPermission();
      return await FirebaseMessaging.instance.getToken();
    } catch (_) {
      return null;
    }
  }

  Future<void> _registerUser() async {
    if (nameCtrl.text.trim().isEmpty || phoneCtrl.text.trim().isEmpty) {
      _showSnack("Please fill in all fields.");
      return;
    }

    setState(() => isLoading = true);
    try {
      final pos = await _getLocation();
      final fcmToken = await _getFcmToken();
      print("FCM TOKEN: $fcmToken");

      final res = await http.post(
        Uri.parse("$baseUrl/users/"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "phone_number": phoneCtrl.text.trim(),
          "full_name": nameCtrl.text.trim(),
          "blood_type": bloodType,
          "latitude": pos.latitude,
          "longitude": pos.longitude,
          "fcm_token": fcmToken,
        }),
      );

      if (res.statusCode == 201) {
        final data = jsonDecode(res.body);
        setState(() => userId = data["id"]);
        _showSnack("Registered! ID saved as active donor.");
      } else {
        _showSnack("Registration Error: ${res.body}");
      }
    } catch (e) {
      _showSnack("Connection error: $e");
    } finally {
      setState(() => isLoading = false);
    }
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Blood Response System")),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    const Text(
                      "Donor Registration",
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(
                        labelText: "Full name",
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: phoneCtrl,
                      decoration: const InputDecoration(
                        labelText: "Phone (+92...)",
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.phone,
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          "Blood Type:",
                          style: TextStyle(fontSize: 16),
                        ),
                        DropdownButton<String>(
                          value: bloodType,
                          items: bloodTypes
                              .map(
                                (t) =>
                                    DropdownMenuItem(value: t, child: Text(t)),
                              )
                              .toList(),
                          onChanged: (v) => setState(() => bloodType = v!),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: isLoading ? null : _registerUser,
                      icon: isLoading
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.person_add),
                      label: const Text("Register as Donor"),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            if (userId != null)
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => RequestScreen(requesterId: userId!),
                  ),
                ),
                icon: const Icon(Icons.emergency),
                label: const Text(
                  "Post Urgent Blood Request",
                  style: TextStyle(fontSize: 16),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class RequestScreen extends StatefulWidget {
  final String requesterId;
  const RequestScreen({super.key, required this.requesterId});

  @override
  State<RequestScreen> createState() => _RequestScreenState();
}

class _RequestScreenState extends State<RequestScreen> {
  final hospitalCtrl = TextEditingController();
  final unitsCtrl = TextEditingController(text: "1");
  String bloodType = "O-";
  final bloodTypes = ["O-", "O+", "A-", "A+", "B-", "B+", "AB-", "AB+"];

  List<dynamic> matches = [];
  Map<String, String> responsesState = {};
  String? currentRequestId;
  bool isSearching = false;

  @override
  void dispose() {
    hospitalCtrl.dispose();
    unitsCtrl.dispose();
    super.dispose();
  }

  Future<void> _submitRequest() async {
    if (hospitalCtrl.text.trim().isEmpty) {
      _showSnack("Enter hospital name.");
      return;
    }

    setState(() {
      isSearching = true;
      matches.clear();
      responsesState.clear();
    });

    try {
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      final pos = await Geolocator.getCurrentPosition();

      final res = await http.post(
        Uri.parse("$baseUrl/blood-requests/"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "requester_id": widget.requesterId,
          "blood_type_needed": bloodType,
          "units_needed": int.tryParse(unitsCtrl.text) ?? 1,
          "hospital_name": hospitalCtrl.text.trim(),
          "latitude": pos.latitude,
          "longitude": pos.longitude,
          "urgency": "critical",
        }),
      );

      if (res.statusCode == 201) {
        final data = jsonDecode(res.body);
        currentRequestId = data["id"];

        final matchRes = await http.get(
          Uri.parse("$baseUrl/blood-requests/$currentRequestId/matches"),
        );

        if (matchRes.statusCode == 200) {
          setState(() {
            matches = jsonDecode(matchRes.body)["matches"] ?? [];
          });
          _fetchResponses();
        }
      } else {
        _showSnack("Failed to create request: ${res.body}");
      }
    } catch (e) {
      _showSnack("Error querying matching donors: $e");
    } finally {
      setState(() => isSearching = false);
    }
  }

  Future<void> _respond(String donorId, String status) async {
    if (currentRequestId == null) return;

    try {
      final res = await http.post(
        Uri.parse("$baseUrl/blood-requests/$currentRequestId/respond"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"donor_id": donorId, "status": status}),
      );

      if (res.statusCode == 201) {
        setState(() {
          responsesState[donorId] = status;
        });
        _showSnack("Response recorded as $status");
      } else {
        _showSnack("Failed to submit response: ${res.body}");
      }
    } catch (e) {
      _showSnack("Error connecting to server: $e");
    }
  }

  Future<void> _fetchResponses() async {
    if (currentRequestId == null) return;
    try {
      final res = await http.get(
        Uri.parse("$baseUrl/blood-requests/$currentRequestId/responses"),
      );
      if (res.statusCode == 200) {
        final List<dynamic> data = jsonDecode(res.body);
        final Map<String, String> updatedMap = {};
        for (var item in data) {
          updatedMap[item["donor_id"]] = item["status"];
        }
        setState(() {
          responsesState = updatedMap;
        });
      }
    } catch (_) {}
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Urgent Blood Request")),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: hospitalCtrl,
              decoration: const InputDecoration(
                labelText: "Hospital Name",
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: unitsCtrl,
                    decoration: const InputDecoration(
                      labelText: "Units Needed",
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: bloodType,
                    decoration: const InputDecoration(
                      labelText: "Blood Type",
                      border: OutlineInputBorder(),
                    ),
                    items: bloodTypes
                        .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                        .toList(),
                    onChanged: (v) => setState(() => bloodType = v!),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: isSearching ? null : _submitRequest,
                icon: isSearching
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.search),
                label: const Text("Find Donors Near Me"),
              ),
            ),
            const Divider(height: 30),
            if (currentRequestId != null)
              Container(
                padding: const EdgeInsets.all(8),
                color: Colors.amber.shade50,
                child: const Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.amber, size: 20),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        "Demo Mode: Tap check/cross to simulate donor accepting or declining.",
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 8),
            Expanded(
              child: matches.isEmpty
                  ? Center(
                      child: Text(
                        isSearching
                            ? "Locating nearest donors..."
                            : "No search triggered or no nearby donors found.",
                        style: const TextStyle(color: Colors.grey),
                      ),
                    )
                  : ListView.builder(
                      itemCount: matches.length,
                      itemBuilder: (_, i) {
                        final donor = matches[i];
                        final donorId = donor["id"];
                        final currentStatus = responsesState[donorId];

                        return Card(
                          margin: const EdgeInsets.symmetric(vertical: 6),
                          child: ListTile(
                            title: Text(
                              donor["full_name"] ?? "Anonymous Donor",
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            subtitle: Text(
                              "${donor['blood_type']} · ${donor['distance_km']} km away\nPhone: ${donor['phone_number']}",
                            ),
                            isThreeLine: true,
                            trailing: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                if (currentStatus != null)
                                  Chip(
                                    labelPadding: const EdgeInsets.symmetric(
                                      horizontal: 4,
                                    ),
                                    avatar: Icon(
                                      currentStatus == "accepted"
                                          ? Icons.check_circle
                                          : Icons.cancel,
                                      color: currentStatus == "accepted"
                                          ? Colors.green
                                          : Colors.red,
                                      size: 16,
                                    ),
                                    label: Text(
                                      currentStatus.toUpperCase(),
                                      style: const TextStyle(fontSize: 10),
                                    ),
                                  )
                                else
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        icon: const Icon(
                                          Icons.check_circle,
                                          color: Colors.green,
                                        ),
                                        onPressed: () =>
                                            _respond(donorId, "accepted"),
                                        tooltip: "Accept Request",
                                      ),
                                      IconButton(
                                        icon: const Icon(
                                          Icons.cancel,
                                          color: Colors.red,
                                        ),
                                        onPressed: () =>
                                            _respond(donorId, "declined"),
                                        tooltip: "Decline Request",
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
          ],
        ),
      ),
    );
  }
}
