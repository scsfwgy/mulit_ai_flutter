import 'dart:convert';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Scaffold, SelectableText;

import 'package:mulit_ai_flutter/core/attachment_store.dart';
import 'package:mulit_ai_flutter/core/chat_attachment.dart';
import 'package:mulit_ai_flutter/i18n/strings.dart';
import 'package:mulit_ai_flutter/ui/ios_style.dart';

class ChatAttachments extends StatelessWidget {
  const ChatAttachments({super.key, required this.attachments, this.onRemove});
  final List<ChatAttachment> attachments;
  final ValueChanged<ChatAttachment>? onRemove;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: attachments
        .map(
          (attachment) => _AttachmentTile(
            attachment: attachment,
            onRemove: onRemove == null ? null : () => onRemove!(attachment),
          ),
        )
        .toList(),
  );
}

class _AttachmentTile extends StatelessWidget {
  const _AttachmentTile({required this.attachment, this.onRemove});
  final ChatAttachment attachment;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) => Container(
    width: 142,
    decoration: BoxDecoration(
      color: IosColors.surface,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: IosColors.separator),
    ),
    child: Row(
      children: [
        Expanded(
          child: CupertinoButton(
            padding: const EdgeInsets.all(8),
            onPressed: () => Navigator.of(context).push(
              appPageRoute<void>(
                builder: (_) => _AttachmentPreview(attachment: attachment),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (attachment.isImage)
                  FutureBuilder<File>(
                    future: AttachmentStore.instance.file(attachment),
                    builder: (context, snapshot) => ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: snapshot.hasData
                          ? Image.file(
                              snapshot.data!,
                              height: 58,
                              width: double.infinity,
                              fit: BoxFit.cover,
                              cacheWidth: 256,
                              errorBuilder: (_, _, _) =>
                                  const Icon(CupertinoIcons.photo),
                            )
                          : const SizedBox(
                              height: 58,
                              child: Icon(CupertinoIcons.photo),
                            ),
                    ),
                  )
                else
                  Icon(
                    attachment.isPdf
                        ? CupertinoIcons.doc_richtext
                        : CupertinoIcons.doc_text,
                    color: IosColors.blue,
                    size: 26,
                  ),
                const SizedBox(height: 4),
                Text(
                  attachment.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: IosColors.label, fontSize: 12),
                ),
                Text(
                  '${(attachment.size / 1024).ceil()} KB',
                  style: TextStyle(color: IosColors.secondary, fontSize: 11),
                ),
              ],
            ),
          ),
        ),
        if (onRemove != null)
          CupertinoButton(
            padding: EdgeInsets.zero,
            minimumSize: const Size(32, 44),
            onPressed: onRemove,
            child: Icon(
              CupertinoIcons.xmark_circle_fill,
              size: 20,
              color: IosColors.secondary,
              semanticLabel: F('i18n.attachment_remove', [attachment.name]),
            ),
          ),
      ],
    ),
  );
}

class _AttachmentPreview extends StatelessWidget {
  const _AttachmentPreview({required this.attachment});
  final ChatAttachment attachment;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: IosColors.background,
    appBar: iosAppBar(
      title: attachment.name,
      leading: IosNavButton(
        icon: CupertinoIcons.back,
        onPressed: () => Navigator.pop(context),
      ),
    ),
    body: SafeArea(
      child: attachment.isPdf
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  T('i18n.attachment_pdf_preview'),
                  style: TextStyle(color: IosColors.secondary),
                ),
              ),
            )
          : attachment.isImage
          ? FutureBuilder<File>(
              future: AttachmentStore.instance.file(attachment),
              builder: (context, snapshot) => snapshot.hasData
                  ? Center(
                      child: InteractiveViewer(
                        child: Image.file(
                          snapshot.data!,
                          cacheWidth: 2048,
                          errorBuilder: (_, _, _) =>
                              Text(T('i18n.attachment_unavailable')),
                        ),
                      ),
                    )
                  : snapshot.hasError
                  ? Center(child: Text(T('i18n.attachment_unavailable')))
                  : const Center(child: CupertinoActivityIndicator()),
            )
          : FutureBuilder(
              future: AttachmentStore.instance.read(attachment),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(child: Text(T('i18n.attachment_unavailable')));
                }
                if (!snapshot.hasData) {
                  return const Center(child: CupertinoActivityIndicator());
                }
                return SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: SelectableText(
                    utf8.decode(snapshot.data!),
                    style: TextStyle(color: IosColors.label),
                  ),
                );
              },
            ),
    ),
  );
}
