import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:excel/excel.dart' as excel;
import 'package:csv/csv.dart';
import 'dart:convert';
import 'dart:html' as html;
import '../widgets/background_widget.dart';
import 'login_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final _rollNoController = TextEditingController();
  final _nameController = TextEditingController();
  final _passingMarksController = TextEditingController(text: '35'); // Default passing marks
  bool _isLoading = false;
  Map<String, dynamic>? _result;
  String? _error;
  late final DatabaseReference _database;
  late final User? _currentUser;

  // Define student detail fields
  final List<String> studentFields = ['Roll No', 'Name', 'Age', 'Gender', 'Section', 'Class'];

  @override
  void initState() {
    super.initState();
    _currentUser = FirebaseAuth.instance.currentUser;
    _database = FirebaseDatabase.instance.ref();
    // Check authentication status
    if (_currentUser == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Navigator.pushReplacementNamed(context, '/');
      });
    }
  }

  Future<void> _checkAuthAndProceed(Future<void> Function() operation) async {
    try {
      // Check if user is authenticated
      if (FirebaseAuth.instance.currentUser == null) {
        throw Exception('User not authenticated');
      }
      await operation();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().contains('permission_denied')
                ? 'Permission denied. Please check database rules.'
                : 'Error: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
      rethrow;
    }
  }

  double _calculatePercentage(Map<String, dynamic> subjects, List<String> academicSubjects) {
    if (subjects.isEmpty) return 0.0;
    
    double totalMarks = 0;
    int totalSubjects = 0;
    
    subjects.forEach((subject, marks) {
      // Only include academic subjects and exclude 'Section' field
      if (academicSubjects.contains(subject) && subject != 'Section') {
        try {
          double mark = double.parse(marks.toString());
          totalMarks += mark;
          totalSubjects++;
        } catch (e) {
          // Skip if marks can't be parsed to double
        }
      }
    });
    
    if (totalSubjects == 0) return 0.0;
    return (totalMarks / (totalSubjects * 100)) * 100;
  }

  String _getGrade(double percentage, Map<String, dynamic> subjects, List<String> academicSubjects) {
    final passingMarks = double.tryParse(_passingMarksController.text) ?? 35;
    int failedSubjects = 0;
    
    // Count failed subjects
    subjects.forEach((subject, marks) {
      if (academicSubjects.contains(subject) && subject != 'Section') {
        try {
          double mark = double.parse(marks.toString());
          if (mark < passingMarks) {
            failedSubjects++;
          }
        } catch (e) {
          // Skip if marks can't be parsed
        }
      }
    });

    // If any subject has failing marks, return F
    if (failedSubjects > 0) {
      return 'F';
    }
    
    // Calculate grade only if all subjects are passed
    if (percentage >= 90) return 'A+';
    if (percentage >= 80) return 'A';
    if (percentage >= 70) return 'B';
    if (percentage >= 60) return 'C';
    if (percentage >= 50) return 'D';
    return 'F';
  }

  String _sanitizeKey(String key) {
    // First, trim whitespace and convert to lowercase for consistency
    String sanitized = key.trim().toLowerCase();
    // Replace any invalid characters with underscores
    sanitized = sanitized.replaceAll(RegExp(r'[.#$\[\]/\s]'), '_');
    // Replace any other non-alphanumeric characters
    sanitized = sanitized.replaceAll(RegExp(r'[^a-z0-9_]'), '_');
    // Ensure the key doesn't start with a number
    if (RegExp(r'^[0-9]').hasMatch(sanitized)) {
      sanitized = 'n_$sanitized';
    }
    // Remove consecutive underscores
    sanitized = sanitized.replaceAll(RegExp(r'_+'), '_');
    // Remove leading/trailing underscores
    sanitized = sanitized.replaceAll(RegExp(r'^_+|_+$'), '');
    // If empty after sanitization, provide a default
    if (sanitized.isEmpty) {
      sanitized = 'field';
    }
    return sanitized;
  }

  Future<void> _uploadFile() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv', 'xlsx'],
        withData: true,
      );

      if (result != null) {
        setState(() {
          _isLoading = true;
        });

        await _checkAuthAndProceed(() async {
          final bytes = result.files.single.bytes;
          final extension = result.files.single.extension;

          if (extension == 'csv') {
            final csvString = String.fromCharCodes(bytes!);
            final rows = const CsvToListConverter().convert(csvString);
            await _processAndStoreData(rows);
          } else if (extension == 'xlsx') {
            final excelFile = excel.Excel.decodeBytes(bytes!);
            await _processAndStoreExcelData(excelFile);
          }
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('File uploaded successfully')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error uploading file: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _processAndStoreData(List<List<dynamic>> rows) async {
    if (rows.isEmpty) {
      throw Exception('File is empty');
    }

    // Get headers from first row and sanitize them
    final rawHeaders = rows[0].map((e) => e.toString().trim()).toList();
    final headers = rawHeaders.map((e) => _sanitizeKey(e)).toList();
    
    if (headers.isEmpty) {
      throw Exception('No headers found in file');
    }

    // Create a mapping between original and sanitized headers
    final headerMapping = Map.fromIterables(headers, rawHeaders);

    // Get academic subjects (excluding student details)
    final academicSubjects = rawHeaders
        .where((header) => !studentFields.contains(header))
        .toList();

    // Process data rows
    for (var i = 1; i < rows.length; i++) {
      final row = rows[i];
      if (row.isEmpty) continue;
      
      final originalRollNo = row[0].toString().trim();
      final rollNo = originalRollNo;
      if (rollNo.isEmpty) continue;

      // Store marks in a separate structure
      final marks = <String, String>{};
      final details = <String, String>{};
      
      // Process each column
      for (var j = 0; j < row.length && j < headers.length; j++) {
        if (row[j] != null) {
          final value = row[j].toString().trim();
          final header = headers[j];
          final originalKey = headerMapping[header];
          
          if (originalKey != null) {
            if (academicSubjects.contains(originalKey)) {
              marks[originalKey] = value;
            } else {
              details[originalKey] = value;
            }
          }
        }
      }

      // Calculate percentage and grade using the marks
      final percentage = _calculatePercentageFromMarks(marks);
      final grade = _getGradeFromMarks(percentage, marks);

      // Store data in a structured way
      await _database.child('marksheets').child(rollNo).set({
        'student_info': {
          'roll_no': originalRollNo,
          'name': details['Name'] ?? '',
          'age': details['Age'] ?? '',
          'gender': details['Gender'] ?? '',
          'section': details['Section'] ?? '',
          'class': details['Class'] ?? '',
        },
        'academic_marks': marks,
        'results': {
          'percentage': percentage.toStringAsFixed(2),
          'grade': grade,
          'passing_marks': _passingMarksController.text,
        },
        'metadata': {
          'academic_subjects': academicSubjects,
          'uploaded_by': FirebaseAuth.instance.currentUser?.email,
          'uploaded_at': ServerValue.timestamp,
        }
      });

      print('Upload Debug Info:');
      print('Roll No: $rollNo');
      print('Student Name: ${details['Name']}');
      print('Academic Subjects: $academicSubjects');
      print('Marks: $marks');
    }
  }

  double _calculatePercentageFromMarks(Map<String, String> marks) {
    if (marks.isEmpty) return 0.0;
    
    double totalMarks = 0;
    int totalSubjects = 0;
    
    marks.forEach((_, value) {
      try {
        double mark = double.parse(value);
        totalMarks += mark;
        totalSubjects++;
      } catch (e) {
        // Skip if marks can't be parsed to double
      }
    });
    
    if (totalSubjects == 0) return 0.0;
    return (totalMarks / (totalSubjects * 100)) * 100;
  }

  String _getGradeFromMarks(double percentage, Map<String, String> marks) {
    final passingMarks = double.tryParse(_passingMarksController.text) ?? 35;
    int failedSubjects = 0;
    
    marks.forEach((_, value) {
      try {
        double mark = double.parse(value);
        if (mark < passingMarks) {
          failedSubjects++;
        }
      } catch (e) {
        // Skip if marks can't be parsed
      }
    });

    if (failedSubjects > 0) {
      return 'F';
    }
    
    if (percentage >= 90) return 'A+';
    if (percentage >= 80) return 'A';
    if (percentage >= 70) return 'B';
    if (percentage >= 60) return 'C';
    if (percentage >= 50) return 'D';
    return 'F';
  }

  Future<void> _processAndStoreExcelData(excel.Excel excel) async {
    final sheet = excel.tables.keys.first;
    final rows = excel.tables[sheet]!.rows;
    
    if (rows.isEmpty) {
      throw Exception('File is empty');
    }

    // Convert Excel rows to List<List<dynamic>> format
    final List<List<dynamic>> convertedRows = rows.map((row) {
      return row.map((cell) => cell?.value.toString() ?? '').toList();
    }).toList();

    // Use the same processing logic as CSV
    await _processAndStoreData(convertedRows);
  }

  Future<void> _searchResult() async {
    if (_rollNoController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a roll number')),
      );
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
      _result = null;
    });

    try {
      await _checkAuthAndProceed(() async {
        final rollNo = _rollNoController.text.trim();
        final searchName = _nameController.text.trim();

        print('Search Debug:');
        print('Roll No: $rollNo');
        print('Search Name: $searchName');

        // Try exact roll number match
        final snapshot = await _database
            .child('marksheets')
            .child(rollNo)
            .get();

        print('Snapshot exists: ${snapshot.exists}');
        if (snapshot.exists) {
          print('Found data: ${snapshot.value}');
        }

        if (snapshot.exists) {
          final data = Map<String, dynamic>.from(snapshot.value as Map);
          
          if (searchName.isNotEmpty) {
            final storedName = data['student_info']?['name']?.toString().trim().toLowerCase() ?? '';
            final searchNameLower = searchName.toLowerCase();
            
            print('Stored Name (lower): $storedName');
            print('Search Name (lower): $searchNameLower');
            
            if (storedName.contains(searchNameLower) || searchNameLower.contains(storedName)) {
              setState(() {
                _result = data;
              });
            } else {
              setState(() {
                _error = 'No result found for this roll number and name combination';
              });
            }
          } else {
            setState(() {
              _result = data;
            });
          }
        } else {
          setState(() {
            _error = 'No result found for this roll number';
          });
        }

        // Print all available entries in the database for debugging
        final allEntriesSnapshot = await _database.child('marksheets').get();
        print('\nAll Available Entries:');
        if (allEntriesSnapshot.exists) {
          final allData = Map<String, dynamic>.from(allEntriesSnapshot.value as Map);
          allData.forEach((key, value) {
            final data = value as Map<String, dynamic>;
            print('Key: $key');
            print('Name: ${data['student_info']?['name']}');
            print('Roll No: ${data['student_info']?['roll_no']}');
            print('---');
          });
        } else {
          print('No entries found in database');
        }
      });
    } catch (e) {
      print('Search Error: $e');
      setState(() {
        _error = 'Error searching result: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final displayName = user?.displayName ?? 'User';

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Text('Student Marksheet System'),
            const Spacer(),
            // User profile section
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircleAvatar(
                  backgroundColor: Colors.blue.shade100,
                  child: Text(
                    displayName[0].toUpperCase(),
                    style: TextStyle(
                      color: Colors.blue.shade900,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  displayName,
                  style: const TextStyle(fontSize: 14),
                ),
                const SizedBox(width: 16),
                // Sign out button
                TextButton.icon(
                  onPressed: () async {
                    final shouldLogout = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('Sign Out'),
                        content: const Text('Are you sure you want to sign out?'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(false),
                            child: const Text('Cancel'),
                          ),
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(true),
                            child: const Text(
                              'Sign Out',
                              style: TextStyle(color: Colors.red),
                            ),
                          ),
                        ],
                      ),
                    );

                    if (shouldLogout == true) {
                      await FirebaseAuth.instance.signOut();
                      if (mounted) {
                        Navigator.of(context).pushReplacement(
                          MaterialPageRoute(builder: (context) => const LoginScreen()),
                        );
                      }
                    }
                  },
                  icon: const Icon(Icons.logout, size: 20),
                  label: const Text('Sign Out'),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.red,
                  ),
                ),
              ],
            ),
          ],
        ),
        backgroundColor: Colors.blue.shade900,
        foregroundColor: Colors.white,
      ),
      body: BackgroundWidget(
        padding: const EdgeInsets.all(16.0),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Card(
                elevation: 4,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Search Student Result',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: Colors.blue.shade900,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _rollNoController,
                        decoration: InputDecoration(
                          labelText: 'Enter Roll Number',
                          prefixIcon: const Icon(Icons.numbers),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        keyboardType: TextInputType.number,
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _nameController,
                        decoration: InputDecoration(
                          labelText: 'Enter Student Name (Optional)',
                          prefixIcon: const Icon(Icons.person),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _passingMarksController,
                        decoration: InputDecoration(
                          labelText: 'Enter Passing Marks',
                          prefixIcon: const Icon(Icons.grade),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        keyboardType: TextInputType.number,
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        height: 50,
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : _searchResult,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue.shade900,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: _isLoading
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                  ),
                                )
                              : const Text(
                                  'Search',
                                  style: TextStyle(fontSize: 16),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              if (_error != null)
                Card(
                  color: Colors.red.shade50,
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Text(
                      _error!,
                      style: TextStyle(color: Colors.red.shade900),
                    ),
                  ),
                ),
              if (_result != null) ...[
                const SizedBox(height: 16),
                _buildResultCard(context),
              ],
              const SizedBox(height: 16),
              SizedBox(
                height: 50,
                child: ElevatedButton.icon(
                  onPressed: _isLoading ? null : _uploadFile,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue.shade900,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: const Icon(Icons.upload_file),
                  label: const Text('Upload Marksheet'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildResultCard(BuildContext context) {
    if (_result == null) return const SizedBox.shrink();

    try {
      // Get the data from the result with proper null checking and type casting
      final Map<String, dynamic> studentInfo = 
          Map<String, dynamic>.from(_result!['student_info'] as Map<dynamic, dynamic>? ?? {});
      
      final Map<String, dynamic> academicMarksRaw = 
          Map<String, dynamic>.from(_result!['academic_marks'] as Map<dynamic, dynamic>? ?? {});
      
      final Map<String, dynamic> results = 
          Map<String, dynamic>.from(_result!['results'] as Map<dynamic, dynamic>? ?? {});
      
      final Map<String, dynamic> metadata = 
          Map<String, dynamic>.from(_result!['metadata'] as Map<dynamic, dynamic>? ?? {});
      
      final List<String> academicSubjects = 
          List<String>.from(metadata['academic_subjects'] as List<dynamic>? ?? []);

      // Convert academic marks to the correct type with proper null handling
      final Map<String, String> academicMarks = 
          academicMarksRaw.map((key, value) => MapEntry(key, value?.toString() ?? ''));

      // Use current passing marks instead of stored ones
      final passingMarks = double.tryParse(_passingMarksController.text) ?? 35;

      // Count failed subjects based on current passing marks
      int failedSubjects = 0;
      academicMarks.forEach((subject, marks) {
        try {
          double mark = double.parse(marks);
          if (mark < passingMarks) {
            failedSubjects++;
          }
        } catch (e) {
          // Skip if marks can't be parsed
        }
      });

      // Recalculate percentage and grade with current passing marks
      final percentage = _calculatePercentageFromMarks(academicMarks);
      final grade = _getGradeFromMarks(percentage, academicMarks);

      return Card(
        elevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(15),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Roll Number: ${studentInfo['roll_no'] ?? ''}',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: grade == 'F' ? Colors.red[100] : Colors.green[100],
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        'Grade: $grade',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: grade == 'F' ? Colors.red[700] : Colors.green[700],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              _buildSection(
                'Student Details',
                [
                  _buildDetailRow('Name', studentInfo['name']?.toString()),
                  _buildDetailRow('Age', studentInfo['age']?.toString()),
                  _buildDetailRow('Gender', studentInfo['gender']?.toString()),
                  _buildDetailRow('Section', studentInfo['section']?.toString()),
                  _buildDetailRow('Class', studentInfo['class']?.toString()),
                ],
              ),
              const SizedBox(height: 24),
              _buildSection(
                'Subject Marks',
                academicMarks.entries.map((e) => _buildSubjectRow(e.key, e.value, passingMarks)).toList(),
              ),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Passing Marks: $passingMarks',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'Failed Subjects: $failedSubjects',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: failedSubjects > 0 ? Colors.red[700] : Colors.green[700],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Percentage: ${percentage.toStringAsFixed(2)}%',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: failedSubjects > 0 ? Colors.red[700] : Colors.blue[700],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    } catch (e) {
      print('Error building result card: $e');
      return Card(
        color: Colors.red[50],
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: Colors.red[200]!),
        ),
        child: const Padding(
          padding: EdgeInsets.all(16.0),
          child: Text('Error displaying result. Please try again.'),
        ),
      );
    }
  }

  Widget _buildSection(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.grey[50],
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.grey[200]!),
          ),
          child: Column(children: children),
        ),
      ],
    );
  }

  Widget _buildDetailRow(String label, String? value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.w500,
                color: Colors.grey,
              ),
            ),
          ),
          const Text(': '),
          Expanded(
            flex: 3,
            child: Text(
              value ?? '',
              style: const TextStyle(
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSubjectRow(String subjectName, String value, double passingMarks) {
    final double? numericValue = double.tryParse(value);
    final bool isPassing = numericValue != null && numericValue >= passingMarks;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(
              subjectName,
              style: const TextStyle(
                fontWeight: FontWeight.w500,
                color: Colors.grey,
              ),
            ),
          ),
          const Text(': '),
          Expanded(
            flex: 3,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: isPassing ? Colors.green[50] : Colors.red[50],
                borderRadius: BorderRadius.circular(15),
                border: Border.all(
                  color: isPassing ? Colors.green[200]! : Colors.red[200]!,
                ),
              ),
              child: Text(
                value,
                style: TextStyle(
                  color: isPassing ? Colors.green[700] : Colors.red[700],
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _rollNoController.dispose();
    _nameController.dispose();
    _passingMarksController.dispose();
    super.dispose();
  }
} 