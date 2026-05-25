import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import '../analytics_service.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({
    super.key,
    this.requireCompletion = false,
    this.onCompleted,
  });

  final bool requireCompletion;
  final VoidCallback? onCompleted;

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  static const _primaryColor = Color.fromARGB(255, 6, 213, 192);
  static const List<String> _sexOptions = ['女性', '男性', '雙性', '間性', '其他'];
  static const List<String> _genderIdentityOptions = [
    '女性',
    '男性',
    '跨性別女性',
    '跨性別男性',
    '非二元',
    '其他'
  ];
  static const List<String> _livingStatusOptions = [
    '獨居',
    '與家人同住',
    '與伴侶同住',
    '與朋友同住',
    '宿舍',
    '其他'
  ];

  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;

  String? _photoUrl;
  String _displayName = '使用者';
  String _email = '';
  String? _sexAssignedAtBirth;
  String? _genderIdentity;
  String? _livingStatus;
  DateTime? _birthday;
  bool _isUploading = false;
  bool _isLoading = true;

  final _nameController = TextEditingController();
  final _diagnosisController = TextEditingController();
  final _residenceController = TextEditingController();
  final _occupationController = TextEditingController();

  @override
  void initState() {
    super.initState();
    AnalyticsService.logPage('profile_page');
    _loadUserData();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _diagnosisController.dispose();
    _residenceController.dispose();
    _occupationController.dispose();
    super.dispose();
  }

  String? _readString(dynamic value) {
    if (value == null) return null;
    final text = value.toString().trim();
    return text.isEmpty ? null : text;
  }

  DateTime? _parseBirthday(dynamic value) {
    if (value is Timestamp) {
      return value.toDate();
    }
    if (value is String && value.trim().isNotEmpty) {
      return DateTime.tryParse(value.trim());
    }
    return null;
  }

  String _formatBirthday(DateTime date) {
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  int? _ageFromBirthday(DateTime? birthday) {
    if (birthday == null) return null;
    final now = DateTime.now();
    var age = now.year - birthday.year;
    final birthdayThisYear = DateTime(now.year, birthday.month, birthday.day);
    if (now.isBefore(birthdayThisYear)) age--;
    return age < 0 ? null : age;
  }

  String? _ageGroupFromBirthday(DateTime? birthday) {
    final age = _ageFromBirthday(birthday);
    if (age == null) return null;
    if (age < 18) return 'under_18';
    if (age <= 24) return '18_24';
    if (age <= 34) return '25_34';
    if (age <= 44) return '35_44';
    if (age <= 54) return '45_54';
    if (age <= 64) return '55_64';
    return '65_plus';
  }

  Future<void> _loadUserData() async {
    User? user = _auth.currentUser;
    if (user == null) return;

    await user.reload();
    user = _auth.currentUser;
    if (user == null) return;

    String name = user.displayName ?? '使用者';
    String diagnosis = '';
    String residence = '';
    String occupation = '';
    String? sexAssignedAtBirth;
    String? genderIdentity;
    String? livingStatus;
    DateTime? birthday;

    try {
      final doc = await _firestore.collection('users').doc(user.uid).get();
      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;
        name = (data['name'] ?? data['nickname'] ?? name).toString();
        diagnosis = (data['diagnosis'] ?? '').toString();
        residence = (data['residence'] ?? '').toString();
        occupation = (data['occupation'] ?? '').toString();
        sexAssignedAtBirth = _readString(data['sexAssignedAtBirth']);
        genderIdentity = _readString(data['genderIdentity']);
        livingStatus = _readString(data['livingStatus']);
        birthday = _parseBirthday(data['birthday']);
      }
    } catch (e) {
      debugPrint('Error loading user profile: $e');
    }

    if (mounted) {
      setState(() {
        _photoUrl = user?.photoURL;
        _displayName = name;
        _email = user?.email ?? '';
        _sexAssignedAtBirth = sexAssignedAtBirth;
        _genderIdentity = genderIdentity;
        _livingStatus = livingStatus;
        _birthday = birthday;
        _nameController.text = name;
        _diagnosisController.text = diagnosis;
        _residenceController.text = residence;
        _occupationController.text = occupation;
        _isLoading = false;
      });
    }
  }

  Future<void> _pickAndUploadImage() async {
    final picker = ImagePicker();
    final XFile? picked = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 800,
      maxHeight: 800,
      imageQuality: 85,
    );
    if (picked == null) return;

    User? user = _auth.currentUser;
    if (user == null) return;

    setState(() => _isUploading = true);
    try {
      final ref = FirebaseStorage.instance
          .ref()
          .child('user_photos')
          .child(user.uid)
          .child('profile.jpg');
      await ref.putFile(File(picked.path));
      final url = await ref.getDownloadURL();
      await user.updatePhotoURL(url);
      await _loadUserData();
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('大頭貼更新成功！')));
      }
    } catch (e) {
      debugPrint('Upload failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('更新失敗，請稍後再試。')));
      }
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  Future<void> _saveProfile() async {
    final user = _auth.currentUser;
    if (user == null) return;

    final newName = _nameController.text.trim();
    final diagnosis = _diagnosisController.text.trim();
    final residence = _residenceController.text.trim();
    final occupation = _occupationController.text.trim();

    if (newName.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('姓名不能為空')));
      return;
    }

    final DateTime? normalizedBirthday = _birthday == null
        ? null
        : DateTime(_birthday!.year, _birthday!.month, _birthday!.day);
    final age = _ageFromBirthday(normalizedBirthday);
    final ageGroup = _ageGroupFromBirthday(normalizedBirthday);

    if (widget.requireCompletion && normalizedBirthday == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('請填寫生日，方便統計年齡層')),
      );
      return;
    }

    try {
      await _firestore.collection('users').doc(user.uid).set(
        {
          'name': newName,
          'nickname': newName,
          'sexAssignedAtBirth': _sexAssignedAtBirth,
          'genderIdentity': _genderIdentity,
          'birthday': normalizedBirthday == null
              ? null
              : Timestamp.fromDate(normalizedBirthday),
          'diagnosis': diagnosis,
          'residence': residence,
          'livingStatus': _livingStatus,
          'occupation': occupation,
          'age': age,
          'ageGroup': ageGroup,
          'birthYear': normalizedBirthday?.year,
          'profileCompleted': true,
          'profileCompletedAt': FieldValue.serverTimestamp(),
          'profileUpdatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
      await AnalyticsService.setUserProperty(
        name: 'age_group',
        value: ageGroup,
      );
      await user.updateDisplayName(newName);
      if (mounted) {
        setState(() {
          _displayName = newName;
        });
        widget.onCompleted?.call();
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('個人資料已更新！')));
      }
    } catch (e) {
      debugPrint('Save failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('儲存失敗，請稍後再試。')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !widget.requireCompletion,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('個人資料'),
          automaticallyImplyLeading: !widget.requireCompletion,
          backgroundColor: _primaryColor,
          foregroundColor: Colors.white,
          actions: [
            TextButton(
              onPressed: _saveProfile,
              child: const Text('儲存',
                  style: TextStyle(color: Colors.white, fontSize: 16)),
            ),
          ],
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                padding:
                    const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
                child: Column(
                  children: [
                    // ── 大頭貼 ──────────────────────────────────────────────
                    GestureDetector(
                      onTap: _isUploading ? null : _pickAndUploadImage,
                      child: Stack(
                        alignment: Alignment.bottomRight,
                        children: [
                          CircleAvatar(
                            radius: 56,
                            backgroundColor: _primaryColor.withOpacity(0.2),
                            backgroundImage: _photoUrl != null && !_isUploading
                                ? NetworkImage(_photoUrl!)
                                : null,
                            child: _isUploading
                                ? const CircularProgressIndicator(
                                    color: _primaryColor)
                                : (_photoUrl == null
                                    ? const Icon(Icons.person,
                                        size: 60, color: _primaryColor)
                                    : null),
                          ),
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: const BoxDecoration(
                              color: _primaryColor,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.camera_alt,
                                size: 18, color: Colors.white),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _email,
                      style:
                          TextStyle(color: Colors.grey.shade600, fontSize: 13),
                    ),
                    const SizedBox(height: 32),

                    // ── 姓名 ────────────────────────────────────────────────
                    _buildField(
                      label: '姓名',
                      controller: _nameController,
                      hint: '輸入你的姓名',
                      maxLength: 30,
                    ),
                    const SizedBox(height: 20),

                    _buildDropdownField(
                      label: '生理性別',
                      value: _sexAssignedAtBirth,
                      hint: '請選擇生理性別',
                      items: _sexOptions,
                      onChanged: (value) {
                        setState(() => _sexAssignedAtBirth = value);
                      },
                    ),
                    const SizedBox(height: 20),

                    _buildDropdownField(
                      label: '身分認同性別',
                      value: _genderIdentity,
                      hint: '請選擇身分認同性別',
                      items: _genderIdentityOptions,
                      onChanged: (value) {
                        setState(() => _genderIdentity = value);
                      },
                    ),
                    const SizedBox(height: 20),

                    _buildDateField(),
                    const SizedBox(height: 20),

                    _buildField(
                      label: '目前診斷',
                      controller: _diagnosisController,
                      hint: '例如：重鬱症、焦慮症（可複數）',
                      maxLength: 120,
                    ),
                    const SizedBox(height: 20),

                    _buildField(
                      label: '居住地',
                      controller: _residenceController,
                      hint: '例如：台北市 / 新北市',
                      maxLength: 60,
                    ),
                    const SizedBox(height: 20),

                    _buildDropdownField(
                      label: '居住狀況',
                      value: _livingStatus,
                      hint: '請選擇居住狀況',
                      items: _livingStatusOptions,
                      onChanged: (value) {
                        setState(() => _livingStatus = value);
                      },
                    ),
                    const SizedBox(height: 20),

                    _buildField(
                      label: '職業',
                      controller: _occupationController,
                      hint: '例如：學生、工程師、自由工作者',
                      maxLength: 60,
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildDateField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '生日',
          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
        ),
        const SizedBox(height: 8),
        InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () async {
            final now = DateTime.now();
            final initial = _birthday ?? DateTime(now.year - 25, 1, 1);
            final selected = await showDatePicker(
              context: context,
              initialDate: initial,
              firstDate: DateTime(1900, 1, 1),
              lastDate: now,
            );
            if (selected != null) {
              setState(() => _birthday = selected);
            }
          },
          child: InputDecorator(
            decoration: InputDecoration(
              hintText: '請選擇生日',
              hintStyle: TextStyle(color: Colors.grey.shade400),
              filled: true,
              fillColor: Colors.grey.shade100,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: _primaryColor, width: 1.5),
              ),
              suffixIcon: const Icon(Icons.calendar_month),
            ),
            child: Text(
              _birthday == null ? '請選擇生日' : _formatBirthday(_birthday!),
              style: TextStyle(
                color:
                    _birthday == null ? Colors.grey.shade500 : Colors.black87,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDropdownField({
    required String label,
    required String? value,
    required String hint,
    required List<String> items,
    required ValueChanged<String?> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          value: value,
          items: items
              .map((item) => DropdownMenuItem<String>(
                    value: item,
                    child: Text(item),
                  ))
              .toList(),
          onChanged: onChanged,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: Colors.grey.shade400),
            filled: true,
            fillColor: Colors.grey.shade100,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: _primaryColor, width: 1.5),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildField({
    required String label,
    required TextEditingController controller,
    required String hint,
    int maxLines = 1,
    int? maxLength,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          maxLines: maxLines,
          maxLength: maxLength,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: Colors.grey.shade400),
            filled: true,
            fillColor: Colors.grey.shade100,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: _primaryColor, width: 1.5),
            ),
            counterStyle: TextStyle(color: Colors.grey.shade400),
          ),
        ),
      ],
    );
  }
}
