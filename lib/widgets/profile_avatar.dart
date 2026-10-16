import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class ProfileAvatar extends StatefulWidget {
  const ProfileAvatar({
    super.key,
    this.size = 40,
    this.userId,
    this.googlePhotoUrl,
  });

  final double size;
  final String? userId;
  final String? googlePhotoUrl;

  @override
  State<ProfileAvatar> createState() => _ProfileAvatarState();
}

class _ProfileAvatarState extends State<ProfileAvatar> {
  Stream<DocumentSnapshot<Map<String, dynamic>>>? _profileStream;
  String? _userId;

  @override
  void initState() {
    super.initState();
    _setProfileStream();
  }

  @override
  void didUpdateWidget(covariant ProfileAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userId != widget.userId) _setProfileStream();
  }

  void _setProfileStream() {
    _userId = widget.userId ?? FirebaseAuth.instance.currentUser?.uid;
    _profileStream = _userId == null
        ? null
        : FirebaseFirestore.instance
              .collection('users')
              .doc(_userId)
              .snapshots();
  }

  @override
  Widget build(BuildContext context) {
    final googlePhotoUrl =
        widget.googlePhotoUrl ?? FirebaseAuth.instance.currentUser?.photoURL;
    final stream = _profileStream;
    if (stream == null) return _buildAvatar(googlePhotoUrl);

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: stream,
      builder: (context, snapshot) {
        final customPhotoUrl = snapshot.data?.data()?['profilePhotoUrl'];
        final photoUrl = customPhotoUrl is String && customPhotoUrl.isNotEmpty
            ? customPhotoUrl
            : googlePhotoUrl;
        return _buildAvatar(photoUrl);
      },
    );
  }

  Widget _buildAvatar(String? photoUrl) {
    return Container(
      width: widget.size,
      height: widget.size,
      decoration: BoxDecoration(
        color: const Color(0xFF1D2030),
        shape: BoxShape.circle,
        border: Border.all(color: const Color(0xFF00E6A7), width: 1.5),
      ),
      clipBehavior: Clip.antiAlias,
      child: photoUrl == null || photoUrl.isEmpty
          ? Icon(
              Icons.person,
              color: const Color(0xFF00E6A7),
              size: widget.size * 0.62,
            )
          : Image.network(
              photoUrl,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => Icon(
                Icons.person,
                color: const Color(0xFF00E6A7),
                size: widget.size * 0.62,
              ),
            ),
    );
  }
}
