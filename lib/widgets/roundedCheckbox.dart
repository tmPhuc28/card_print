import 'package:flutter/material.dart';

class RoundedCheckbox extends StatefulWidget {
  final bool value;
  final ValueChanged<bool> onChanged;
  final String title;
  final IconData? icon;

  const RoundedCheckbox({
    super.key,
    required this.value,
    required this.onChanged,
    required this.title,
    this.icon,
  });

  @override
  _RoundedCheckboxState createState() => _RoundedCheckboxState();
}

class _RoundedCheckboxState extends State<RoundedCheckbox> {
  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {
        widget.onChanged(!widget.value);
      },
      child: Row(
        children: [
          const SizedBox(width: 60),
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: widget.value ? Colors.blue : Colors.grey[300],
              borderRadius: BorderRadius.circular(15),
            ),
            child: widget.value
                ? const Icon(
              Icons.check,
              color: Colors.white,
              size: 20,
            )
                : null,
          ),
          const SizedBox(width: 20),
          Row(
            children: [
              if (widget.icon != null)
                Icon(
                  widget.icon,
                  size: 20,
                  color: Colors.grey,
                ),
              if (widget.icon != null) const SizedBox(width: 8),
              Text(
                widget.title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}