import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class SearchCastBar extends StatefulWidget {
  final Function(String movieTitle) onCast;
  final bool isConnected;

  const SearchCastBar({
    Key? key,
    required this.onCast,
    required this.isConnected,
  }) : super(key: key);

  @override
  State<SearchCastBar> createState() => _SearchCastBarState();
}

class _SearchCastBarState extends State<SearchCastBar> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  final List<String> _quickSuggestions = [
    'Oppenheimer',
    'Inception',
    'Stranger Things',
    'Interstellar',
    'The Dark Knight',
  ];

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _submitCast([String? customText]) {
    final text = customText ?? _controller.text;
    if (text.trim().isNotEmpty) {
      widget.onCast(text.trim());
      _focusNode.unfocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: AppTheme.glassBoxDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.movie_filter_rounded, color: AppTheme.primaryCyan, size: 20),
              const SizedBox(width: 8),
              Text(
                'Cast Movie / Search Title',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontSize: 15),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  focusNode: _focusNode,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => _submitCast(),
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'Type movie title or app name...',
                    prefixIcon: const Icon(Icons.search_rounded, color: AppTheme.textMuted, size: 20),
                    suffixIcon: _controller.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear_rounded, color: AppTheme.textMuted, size: 18),
                            onPressed: () {
                              _controller.clear();
                              setState(() {});
                            },
                          )
                        : null,
                  ),
                  onChanged: (val) => setState(() {}),
                ),
              ),
              const SizedBox(width: 10),
              // Cast Button
              InkWell(
                onTap: widget.isConnected ? () => _submitCast() : null,
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  height: 48,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    gradient: widget.isConnected ? AppTheme.primaryGradient : null,
                    color: widget.isConnected ? null : Colors.white10,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: widget.isConnected
                        ? [
                            BoxShadow(
                              color: AppTheme.primaryCyan.withOpacity(0.4),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            )
                          ]
                        : null,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.cast_rounded,
                        color: widget.isConnected ? Colors.white : AppTheme.textMuted,
                        size: 20,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Cast',
                        style: TextStyle(
                          color: widget.isConnected ? Colors.white : AppTheme.textMuted,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Quick Suggestion Chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: _quickSuggestions.map((title) {
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ActionChip(
                    backgroundColor: const Color(0x1A4FACFE),
                    side: const BorderSide(color: Color(0x334FACFE)),
                    labelStyle: const TextStyle(color: AppTheme.primaryCyan, fontSize: 12),
                    label: Text(title),
                    onPressed: () {
                      _controller.text = title;
                      setState(() {});
                      _submitCast(title);
                    },
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}
