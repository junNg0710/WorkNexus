# FeatureChat port table (Dart → Swift)

Paths of Swift files are relative to `Packages/WorkNexusKit/Sources/FeatureChat/`. Generated from the `/// Ported from:` header of each
file (the Dart side is the first four sources named there). Tests live in `Tests/FeatureChatTests/` (Xxd/, Domain/, Data/, Presentation/).

| Swift | Dart |
|---|---|
| Data/Files/ChatAttachmentLoader.swift | lib/features/chat/data/repositories/chat_attachment_loader.dart |
| Data/Files/ChatFileCache.swift | lib/features/chat/data/datasources/chat_file_cache.dart |
| Data/Files/ChatMediaSupport.swift | lib/features/chat/data/repositories/chat_attachment_loader.dart (top-level helpers), datasources/image_header_size.dart, |
| Data/Local/ChatLocalDatasource.swift | lib/features/chat/data/datasources/chat_local_datasource.dart |
| Data/Local/ChatMigrations.swift | lib/core/database/database.dart |
| Data/Local/ChatTimelineDatasource.swift | lib/features/chat/data/datasources/chat_timeline_datasource.dart |
| Data/Mappers/ChatMappers.swift | lib/features/chat/data/mappers/chat_mappers.dart |
| Data/Repositories/ChatAuxiliary.swift | lib/features/chat/data/repositories/chat_saved_copies.dart<br>lib/features/chat/data/repositories/chat_cache_manager.dart<br>lib/features/chat/data/repositories/chat_avatar_service.dart |
| Data/Repositories/ChatCredentialsResolver.swift | lib/features/chat/data/repositories/chat_credentials_resolver.dart |
| Data/Repositories/ChatHistorySync.swift | lib/features/chat/data/repositories/chat_history_sync.dart |
| Data/Repositories/ChatPacketIngestor.swift | lib/features/chat/data/repositories/chat_packet_ingestor.dart |
| Data/Repositories/ChatSender.swift | lib/features/chat/data/repositories/chat_sender.dart |
| Data/Repositories/ChatSession.swift | lib/features/chat/data/repositories/chat_session.dart |
| Data/Repositories/ChatTypingChannel.swift | lib/features/chat/data/repositories/chat_typing_channel.dart |
| Data/Repositories/LinkPreviewRepository.swift | lib/features/chat/data/datasources/link_preview_parser.dart<br>lib/features/chat/data/datasources/link_preview_http_datasource.dart<br>lib/features/chat/data/repositories/cached_link_preview_repository.dart<br>lib/features/chat/data/repositories/local_message_translation_repository.dart |
| Data/Repositories/StickerRepositories.swift | lib/features/chat/data/repositories/local_sticker_repository.dart<br>lib/features/chat/data/repositories/local_wallpaper_repository.dart<br>lib/features/chat/data/datasources/webp_sticker_converter.dart<br>lib/features/chat/data/datasources/telegram_sticker_source.dart… |
| Data/Repositories/XxdChatRepository.swift | lib/features/chat/data/repositories/xxd_chat_repository.dart |
| Data/Xxd/ApiSchemeCodec.swift | lib/features/chat/data/datasources/xxd/api_scheme_codec.dart |
| Data/Xxd/XxdBackend.swift | lib/features/chat/data/datasources/xxd/xxd_backend.dart |
| Data/Xxd/XxdCipher.swift | lib/features/chat/data/datasources/xxd/xxd_cipher.dart |
| Data/Xxd/XxdConnection.swift | lib/features/chat/data/datasources/xxd/xxd_connection.dart |
| Data/Xxd/XxdConnectionState.swift | lib/features/chat/data/datasources/xxd/xxd_connection_state.dart |
| Data/Xxd/XxdFrameCodec.swift | lib/features/chat/data/datasources/xxd/xxd_frame_codec.dart |
| Data/Xxd/XxdHttpDatasource.swift | lib/features/chat/data/datasources/xxd/xxd_http_datasource.dart |
| Data/Xxd/XxdPacket.swift | lib/features/chat/data/datasources/xxd/xxd_packet.dart |
| Data/Xxd/XxdServerInfo.swift | lib/features/chat/data/datasources/xxd/xxd_server_info.dart |
| Data/Xxd/XxdSigning.swift | lib/features/chat/data/datasources/xxd/xxd_signing.dart |
| Data/Xxd/XxdSocket.swift | lib/features/chat/data/datasources/xxd/xxd_socket.dart |
| Data/Xxd/XxdTLS.swift | lib/features/chat/data/datasources/xxd/xxd_tls.dart |
| Data/Xxd/XxdTrafficLog.swift | lib/features/chat/data/datasources/xxd/xxd_traffic_log.dart |
| Domain/ChatNotification.swift | lib/features/chat/presentation/widgets/chat_notification_listener.dart |
| Domain/Entities/ChatConversation.swift | lib/features/chat/domain/entities/chat_conversation.dart |
| Domain/Entities/ChatMessage.swift | lib/features/chat/domain/entities/chat_message.dart |
| Domain/Entities/ChatMisc.swift | lib/features/chat/domain/entities/link_preview.dart<br>lib/features/chat/domain/entities/message_reaction.dart<br>lib/features/chat/domain/entities/chat_message_translation.dart<br>lib/features/chat/domain/entities/chat_cache_usage.dart |
| Domain/Entities/ChatSticker.swift | lib/features/chat/domain/entities/chat_sticker.dart<br>lib/features/chat/domain/entities/remote_sticker_set.dart |
| Domain/Entities/ChatUser.swift | lib/features/chat/domain/entities/chat_user.dart |
| Domain/Repositories/ChatAuxRepositories.swift | lib/features/chat/domain/repositories/link_preview_repository.dart<br>lib/features/chat/domain/repositories/message_translation_repository.dart<br>lib/features/chat/domain/repositories/sticker_pack_source.dart<br>lib/features/chat/domain/repositories/sticker_repository.dart… |
| Domain/Repositories/ChatRepository.swift | lib/features/chat/domain/repositories/chat_runtime_settings.dart<br>lib/features/chat/domain/repositories/chat_repository.dart |
| Domain/UseCases/ChatNotificationBridge.swift | lib/features/chat/presentation/widgets/chat_notification_listener.dart |
| Domain/UseCases/Emoji.swift | lib/features/chat/domain/usecases/decode_emoji.dart<br>lib/features/chat/domain/usecases/encode_emoji.dart<br>lib/features/chat/domain/usecases/is_single_emoji.dart |
| Domain/UseCases/LinkUseCases.swift | lib/features/chat/domain/usecases/parse_merge_request_link.dart<br>lib/features/chat/domain/usecases/find_linked_merge_request.dart<br>lib/features/chat/domain/usecases/find_linked_ticket.dart<br>lib/features/chat/domain/usecases/parse_sticker_pack_link.dart |
| Domain/UseCases/Mentions.swift | lib/core/util/adjacent_mentions.dart<br>`ParseMessageContent.repairMentions` |
| Domain/UseCases/PagingUseCases.swift | lib/features/chat/domain/usecases/load_older_messages.dart<br>lib/features/chat/domain/usecases/load_newer_messages.dart<br>lib/features/chat/domain/usecases/download_chat_history.dart |
| Domain/UseCases/ParseMessageContent.swift | lib/features/chat/domain/usecases/parse_message_content.dart |
| Domain/UseCases/PolicyUseCases.swift | lib/features/chat/domain/usecases/can_send_to_chat.dart<br>lib/features/chat/domain/usecases/count_badge_unread.dart<br>lib/features/chat/domain/usecases/count_tab_unread.dart<br>lib/features/chat/domain/usecases/resolve_chat_title.dart… |
| Domain/UseCases/ReactionUseCases.swift | lib/features/chat/domain/usecases/build_reactions.dart<br>lib/features/chat/domain/usecases/is_reaction_row.dart<br>lib/features/chat/domain/usecases/retract_message.dart<br>lib/features/chat/domain/usecases/toggle_reaction.dart |
| Domain/UseCases/SendUseCases.swift | lib/features/chat/domain/usecases/send_text_message.dart<br>lib/features/chat/domain/usecases/send_code_message.dart<br>lib/features/chat/domain/usecases/send_chat_file.dart<br>lib/features/chat/domain/usecases/send_sticker.dart… |
| Domain/UseCases/StickerAndTranslateUseCases.swift | lib/features/chat/domain/usecases/import_sticker_pack.dart<br>lib/features/chat/domain/usecases/save_image_as_sticker.dart<br>lib/features/chat/domain/usecases/translate_chat_message.dart |
| Domain/UseCases/TextUseCases.swift | lib/features/chat/domain/usecases/fold_search_text.dart<br>lib/features/chat/domain/usecases/tidy_markdown_emphasis.dart |
| Domain/UseCases/ThreadUseCases.swift | lib/features/chat/domain/usecases/build_reply_thread.dart |
| Domain/ValueObjects/ChatValueObjects.swift | lib/features/chat/domain/value_objects/chat_connection_status.dart |
| Domain/ValueObjects/MessageContent.swift | lib/features/chat/domain/value_objects/message_content.dart |
| Domain/ValueObjects/TypingRoster.swift | lib/features/chat/domain/value_objects/typing_roster.dart |
| Presentation/ChatSettings.swift | lib/core/settings/{app_settings,chat_appearance}.dart |
| Presentation/Composer/ChatComposerController.swift | lib/features/chat/presentation/widgets/chat_composer.dart (`_ChatComposerState`)<br>chat_staged_files_provider.dart |
| Presentation/Composer/ChatComposerModel.swift | lib/features/chat/presentation/widgets/chat_composer_controller.dart<br>chat_mention_text_controller.dart |
| Presentation/Composer/ChatComposerTextView.swift | lib/features/chat/presentation/widgets/{chat_composer_field,chat_composer_input,chat_composer_plain_input,chat_editor_styles}.dart |
| Presentation/Composer/ChatComposerView.swift | lib/features/chat/presentation/widgets/chat_composer.dart |
| Presentation/Composer/ChatMentionEdit.swift | lib/features/chat/presentation/widgets/chat_mention_text_controller.dart |
| Presentation/Composer/ChatMentionList.swift | lib/features/chat/presentation/widgets/{chat_mention_list,chat_mention_overlay}.dart |
| Presentation/Composer/ChatMessageSender.swift | lib/features/chat/presentation/widgets/{chat_text_send,chat_file_send}.dart<br>chat_composer.dart |
| Presentation/Composer/ChatReadOnlyBar.swift | lib/features/chat/presentation/widgets/chat_read_only_bar.dart |
| Presentation/Composer/ChatTypingSender.swift | lib/features/chat/presentation/providers/chat_typing_sender.dart |
| Presentation/Composer/ComposerToolbar.swift | lib/features/chat/presentation/widgets/chat_composer_toolbar.dart<br>chat_markdown_toolbar.dart |
| Presentation/Composer/MarkdownFormatter.swift | lib/features/chat/presentation/widgets/chat_composer_controller.dart |
| Presentation/Composer/MentionAutocomplete.swift | lib/features/chat/presentation/widgets/mention_autocomplete.dart |
| Presentation/Composer/ReplyDraftBanner.swift | lib/features/chat/presentation/widgets/reply_draft_banner.dart |
| Presentation/Composer/SendCodeDialog.swift | lib/features/chat/presentation/widgets/send_code_dialog.dart<br>chat_send_code_button.dart |
| Presentation/Composer/StagedFilesStrip.swift | lib/features/chat/presentation/widgets/chat_staged_files.dart |
| Presentation/Media/AttachmentDownloadBadge.swift | lib/features/chat/presentation/widgets/{attachment_download_badge,cancel_download_button,chat_upload_overlay}.dart |
| Presentation/Media/AttachmentTransfers.swift | lib/features/chat/presentation/widgets/attachment_download.dart |
| Presentation/Media/ChatCodeBody.swift | lib/features/chat/presentation/widgets/message_bubble_content.dart (code branch)<br>core/widgets/code_block.dart |
| Presentation/Media/ChatFileBadge.swift | lib/features/chat/presentation/widgets/{chat_file_badge,chat_file_action_button}.dart |
| Presentation/Media/ChatFileBody.swift | lib/features/chat/presentation/widgets/chat_file_body.dart |
| Presentation/Media/ChatImageBody.swift | lib/features/chat/presentation/widgets/chat_image_body.dart |
| Presentation/Media/ChatImageViewer.swift | lib/features/chat/presentation/widgets/{chat_image_viewer,chat_image_viewer_bar,chat_image_stage,chat_image_context_menu}.dart |
| Presentation/Media/ChatMediaBody.swift | lib/features/chat/presentation/widgets/message_bubble_content.dart |
| Presentation/Media/ChatVideoTile.swift | lib/features/chat/presentation/widgets/{chat_video_tile,chat_video_tile_parts,chat_video_overlays}.dart |
| Presentation/Media/ChatVideoViewer.swift | lib/features/chat/presentation/widgets/{chat_video_dialog,chat_video_controls,chat_floating_video}.dart |
| Presentation/Shell/ChatAvatarView.swift | lib/features/chat/presentation/widgets/chat_avatar.dart |
| Presentation/Shell/ChatFilesPanel.swift | lib/features/chat/presentation/widgets/chat_files_panel.dart |
| Presentation/Shell/ChatHistoryDownloadModel.swift | lib/features/chat/presentation/providers/chat_history_download.dart |
| Presentation/Shell/ChatInfoFilesSection.swift | lib/features/chat/presentation/widgets/chat_info_files_section.dart |
| Presentation/Shell/ChatInfoPanel.swift | lib/features/chat/presentation/widgets/chat_info_panel.dart<br>lib/features/chat/presentation/widgets/chat_detail_row.dart |
| Presentation/Shell/ChatListTabs.swift | lib/features/chat/presentation/widgets/chat_list_tabs.dart<br>lib/features/chat/presentation/widgets/chat_tab_chip.dart |
| Presentation/Shell/ChatListing.swift | lib/features/chat/presentation/widgets/conversation_list_pane.dart<br>lib/features/chat/presentation/widgets/new_chat_people.dart |
| Presentation/Shell/ChatMembersPanel.swift | lib/features/chat/presentation/widgets/chat_members_panel.dart<br>chat_member_list.dart<br>lib/features/chat/presentation/widgets/chat_role_tabs.dart |
| Presentation/Shell/ChatMessageCard.swift | lib/features/chat/presentation/widgets/chat_message_card.dart |
| Presentation/Shell/ChatRootView.swift | lib/features/chat/presentation/pages/chat_page.dart |
| Presentation/Shell/ChatSelfAvatarButton.swift | lib/features/chat/presentation/widgets/chat_self_avatar_button.dart<br>chat_self_menu.dart |
| Presentation/Shell/ChatSharedFiles.swift | lib/features/chat/presentation/widgets/chat_shared_files.dart<br>lib/features/chat/presentation/widgets/chat_media_grid_thumb.dart |
| Presentation/Shell/ChatShellEvents.swift | lib/features/chat/presentation/widgets/chat_notification_banner.dart |
| Presentation/Shell/ChatShellLabels.swift | lib/features/chat/presentation/widgets/chat_labels.dart |
| Presentation/Shell/ChatShellLayout.swift | lib/features/chat/presentation/widgets/chat_layout.dart<br>lib/features/chat/presentation/widgets/chat_panels.dart |
| Presentation/Shell/ChatShellModel+Files.swift | lib/features/chat/presentation/widgets/attachment_download.dart |
| Presentation/Shell/ChatShellModel.swift | lib/features/chat/presentation/providers/chat_providers.dart<br>chat_controller.dart |
| Presentation/Shell/ChatSidePanelFrame.swift | lib/features/chat/presentation/widgets/chat_side_panel_frame.dart<br>lib/features/chat/presentation/widgets/chat_side_panel_host.dart |
| Presentation/Shell/ChatStatusBanner.swift | lib/features/chat/presentation/widgets/chat_status_banner.dart<br>lib/features/chat/presentation/widgets/chat_notification_banner.dart |
| Presentation/Shell/ChatThreadHeader.swift | lib/features/chat/presentation/widgets/chat_thread_header.dart<br>lib/features/chat/presentation/widgets/chat_mute_toggle.dart |
| Presentation/Shell/ChatThreadPane.swift | lib/features/chat/presentation/widgets/thread_pane.dart |
| Presentation/Shell/ChatThreadSearch.swift | lib/features/chat/presentation/providers/chat_search_providers.dart<br>widgets/chat_thread_search_bar.dart |
| Presentation/Shell/ChatThreadSearchBar.swift | lib/features/chat/presentation/widgets/chat_thread_search_bar.dart<br>lib/features/chat/presentation/widgets/chat_search_status.dart<br>lib/features/chat/presentation/widgets/chat_search_period_button.dart<br>lib/features/chat/presentation/widgets/chat_history_download_prompt.dart |
| Presentation/Shell/ChatThreadSession.swift | lib/features/chat/presentation/widgets/thread_pane.dart |
| Presentation/Shell/ChatTrustViews.swift | lib/features/chat/presentation/widgets/chat_trust_gate.dart<br>lib/features/chat/presentation/widgets/chat_trust_dialog.dart<br>lib/features/chat/presentation/widgets/chat_trust_reasons.dart<br>lib/features/chat/presentation/widgets/chat_certificate_card.dart |
| Presentation/Shell/ChatUserProfileDialog.swift | lib/features/chat/presentation/widgets/chat_user_profile_dialog.dart |
| Presentation/Shell/ConversationListPane.swift | lib/features/chat/presentation/widgets/conversation_list_pane.dart |
| Presentation/Shell/ConversationRow.swift | lib/features/chat/presentation/widgets/conversation_row.dart |
| Presentation/Shell/ConversationTile.swift | lib/features/chat/presentation/widgets/conversation_tile.dart<br>lib/features/chat/presentation/widgets/conversation_preview_line.dart<br>lib/features/chat/presentation/widgets/typing_dots.dart |
| Presentation/Shell/NewChatDialog.swift | lib/features/chat/presentation/widgets/new_chat_dialog.dart |
| Presentation/Shell/NewChatPeople.swift | lib/features/chat/presentation/widgets/new_chat_people.dart |
| Presentation/Shell/PinnedMessagesModel.swift | lib/features/chat/presentation/widgets/pinned_messages_panel.dart |
| Presentation/Shell/PinnedMessagesPanel.swift | lib/features/chat/presentation/widgets/pinned_messages_panel.dart |
| Presentation/Shell/ReplyThreadPanel.swift | lib/features/chat/presentation/widgets/reply_thread_panel.dart |
| Presentation/Stickers/ChatEmojiPanel.swift | lib/features/chat/presentation/widgets/{chat_emoji_panel,chat_emoji_picker}.dart |
| Presentation/Stickers/ChatEmojiSidePanel.swift | lib/features/chat/presentation/widgets/chat_emoji_side_panel.dart |
| Presentation/Stickers/ChatStickerGrid.swift | lib/features/chat/presentation/widgets/chat_sticker_grid.dart |
| Presentation/Stickers/ChatStickerImage.swift | lib/features/chat/presentation/widgets/chat_sticker_image.dart |
| Presentation/Stickers/ChatStickerPackBar.swift | lib/features/chat/presentation/widgets/{chat_sticker_pack_bar,chat_sticker_set_buttons}.dart |
| Presentation/Stickers/ChatStickerPanel.swift | lib/features/chat/presentation/widgets/chat_sticker_panel.dart<br>providers/sticker_providers.dart |
| Presentation/Stickers/ImportStickerPackSheet.swift | lib/features/chat/presentation/widgets/import_sticker_pack_dialog.dart |
| Presentation/Stickers/StickerBytesView.swift | lib/features/chat/presentation/widgets/chat_sticker_image.dart |
| Presentation/Stickers/StickerImportJobs.swift | lib/features/chat/presentation/providers/sticker_import_jobs.dart |
| Presentation/Stickers/StickerStore.swift | lib/features/chat/presentation/providers/sticker_providers.dart |
| Presentation/Style/BubbleShape.swift | lib/features/chat/presentation/widgets/bubble_tail.dart |
| Presentation/Style/ChatBubbleInk.swift | lib/features/chat/presentation/widgets/chat_bubble_theme.dart |
| Presentation/Style/ChatColor.swift | lib/core/theme/contrast.dart |
| Presentation/Style/ChatDoodleCanvas.swift | lib/features/chat/presentation/widgets/chat_wallpaper.dart |
| Presentation/Style/ChatDoodlePalette.swift | lib/core/theme/chat_doodle_palette.dart<br>lib/core/settings/chat_wallpaper_color.dart |
| Presentation/Style/ChatStyle.swift | lib/features/chat/presentation/widgets/chat_style.dart |
| Presentation/Style/ChatStylePalette.swift | lib/core/theme/chat_style_palette.dart |
| Presentation/Style/ChatStyleSpecs.swift | lib/features/chat/presentation/widgets/chat_style_specs.dart |
| Presentation/Style/ChatWallpaperView.swift | lib/features/chat/presentation/widgets/chat_wallpaper.dart |
| Presentation/Thread/BubbleLayout.swift | lib/features/chat/presentation/widgets/message_bubble.dart |
| Presentation/Thread/ChatLinkCardFrame.swift | lib/features/chat/presentation/widgets/chat_link_card_frame.dart |
| Presentation/Thread/ChatListRows.swift | lib/features/chat/presentation/widgets/message_list_item.dart |
| Presentation/Thread/ChatMessageWindow.swift | lib/features/chat/presentation/providers/chat_message_window.dart |
| Presentation/Thread/ChatNoticeView.swift | lib/features/chat/presentation/widgets/chat_notice.dart |
| Presentation/Thread/ChatSeparatorView.swift | lib/features/chat/presentation/widgets/chat_separator.dart |
| Presentation/Thread/ChatStrings.swift | lib/l10n/app_en.arb |
| Presentation/Thread/ChatTextBody.swift | lib/features/chat/presentation/widgets/message_body.dart |
| Presentation/Thread/ChatTextLabels.swift | lib/features/chat/presentation/widgets/chat_text_labels.dart<br>chat_labels.dart |
| Presentation/Thread/ChatThreadActions.swift | lib/features/chat/presentation/widgets/chat_profile_tap.dart, forward_message_dialog.dart (the `forward` hook is set by `ChatThreadPane`), save_sticker_action.dart |
| Presentation/Thread/ChatTypingRow.swift | lib/features/chat/presentation/widgets/chat_typing_bubble.dart<br>typing_dots.dart<br>chat_typing_avatars.dart<br>chat_typing_label.dart |
| Presentation/Thread/LinkPreviewCard.swift | lib/features/chat/presentation/widgets/link_preview_card.dart |
| Presentation/Thread/MentionTextView.swift | lib/features/chat/presentation/widgets/mention_text.dart |
| Presentation/Thread/MessageActions.swift | lib/features/chat/presentation/widgets/message_actions.dart |
| Presentation/Thread/MessageBodyView.swift | lib/features/chat/presentation/widgets/message_body.dart |
| Presentation/Thread/MessageBubbleBox.swift | lib/features/chat/presentation/widgets/message_bubble_box.dart |
| Presentation/Thread/MessageBubbleContent.swift | lib/features/chat/presentation/widgets/message_bubble_content.dart |
| Presentation/Thread/MessageBubbleView.swift | lib/features/chat/presentation/widgets/message_bubble.dart |
| Presentation/Thread/MessageFooterView.swift | lib/features/chat/presentation/widgets/message_footer.dart |
| Presentation/Thread/MessageHoverActions.swift | lib/features/chat/presentation/widgets/message_hover_actions.dart<br>message_context_menu.dart |
| Presentation/Thread/MessageLinkPreviews.swift | lib/features/chat/presentation/widgets/message_link_previews.dart |
| Presentation/Thread/MessageListContent.swift | lib/features/chat/presentation/widgets/message_list.dart |
| Presentation/Thread/MessageListHeaderView.swift | lib/features/chat/presentation/widgets/message_list_header.dart<br>scroll_to_latest_button.dart |
| Presentation/Thread/MessageListScroll.swift | lib/features/chat/presentation/widgets/message_list_view.dart<br>message_list.dart |
| Presentation/Thread/MessageListView.swift | lib/features/chat/presentation/widgets/message_list.dart, message_list_view.dart |
| Presentation/Thread/MessageMediaAdapter.swift | lib/features/chat/presentation/widgets/chat_image_body.dart, chat_file_body.dart |
| Presentation/Thread/MessageRowLayout.swift | lib/features/chat/presentation/widgets/message_row.dart |
| Presentation/Thread/MessageSenderNameView.swift | lib/features/chat/presentation/widgets/message_sender_name.dart |
| Presentation/Thread/MessageTimelineModel+Jump.swift | lib/features/chat/presentation/widgets/message_jump.dart<br>message_list_paging.dart |
| Presentation/Thread/MessageTimelineModel+Paging.swift | lib/features/chat/presentation/widgets/message_list_paging.dart |
| Presentation/Thread/MessageTimelineModel+Typing.swift | lib/features/chat/presentation/providers/chat_typing_providers.dart |
| Presentation/Thread/MessageTimelineModel.swift | lib/features/chat/presentation/widgets/message_list.dart (_MessageListState)<br>providers/chat_providers.dart |
| Presentation/Thread/MessageTranslationController.swift | lib/features/chat/presentation/providers/message_translation_controller.dart<br>message_translation_view.dart |
| Presentation/Thread/MessageUnderBubble.swift | lib/features/chat/presentation/widgets/message_under_bubble.dart |
| Presentation/Thread/NotificationBodyView.swift | lib/features/chat/presentation/widgets/notification_body.dart |
| Presentation/Thread/PinnedMessageBar.swift | lib/features/chat/presentation/widgets/pinned_message_bar.dart |
| Presentation/Thread/ReplyMediaThumbView.swift | lib/features/chat/presentation/widgets/reply_media_thumb.dart |
| Presentation/Thread/ReplyQuoteView.swift | lib/features/chat/presentation/widgets/reply_quote.dart |
| Presentation/Thread/ThreadAvatar.swift | lib/features/chat/presentation/widgets/chat_avatar.dart<br>message_avatar_slot.dart<br>chat_typing_avatars.dart |
| Presentation/Thread/ThreadChipView.swift | lib/features/chat/presentation/widgets/thread_chip.dart |
| Presentation/Thread/ThreadReactions.swift | lib/features/chat/presentation/widgets/reaction_chips.dart<br>reaction_picker.dart<br>providers/reaction_controller.dart |
| Presentation/Thread/ThreadRowView.swift | lib/features/chat/presentation/widgets/message_list_item.dart |
| Presentation/Thread/TicketLinkCards.swift | lib/features/chat/presentation/widgets/zentao_ticket_card.dart<br>merge_request_card.dart (fetches through `ChatServices.mergeRequests`, refetches on app resume) |
| Support/ApiSchemeJS.swift | lib/features/chat/data/datasources/xxd/api_scheme_codec.dart) |
| Domain/Repositories/ChatAuxRepositories.swift (`MergeRequestLinkService`) | lib/core/domain/adapters/merge_request_link_service.dart |
| Domain/ValueObjects/ChatVideoPlayback.swift | lib/features/chat/data/datasources/chat_video_stream_server.dart (the proxy's role: ranged bytes of a video) |
| Data/Files/ChatVideoSource.swift | chat_video_stream_server.dart (upstream route) + chat_attachment_loader.dart (`videoStream`) |
| Data/Xxd/XxdRangeStream.swift | chat_video_stream_server.dart (`_serve`, `sliceStream`: pinned ranged GET, a server that ignores `Range` is answered as if it honoured it) |
| Presentation/Avatar/AvatarCropGeometry.swift | lib/features/chat/presentation/widgets/chat_avatar_crop_view.dart (frame maths) |
| Presentation/Avatar/ChatAvatarCropView.swift | chat_avatar_crop_view.dart, chat_avatar_crop_mask.dart |
| Presentation/Avatar/ChatAvatarCropDialog.swift | chat_avatar_crop_dialog.dart (also used for the self-avatar change in `ChatUserProfileDialog`) |
| Presentation/Avatar/ChatGroupAvatarDialog.swift | chat_group_avatar_dialog.dart (opened from the info panel's "Change group picture") |
| Presentation/Media/ChatImageStrip.swift | chat_media_strip.dart (photos only) |
| Presentation/Media/ChatPlayerSurface.swift | video_player's `VideoPlayer` (AVPlayerLayer, no system controls) |
| Presentation/Media/ChatVideoControls.swift | chat_video_controls.dart |
| Presentation/Media/ChatVideoParts.swift | chat_video_tile_parts.dart, chat_video_overlays.dart |
| Presentation/Media/ChatVideoPlayer.swift | providers/chat_video_playback.dart (`openChatVideo`, the player controller) |
| Presentation/Media/ChatVideoPlaybackModel.swift | providers/chat_video_playback.dart (`ChatVideoPlaybackNotifier`, floating / docked); dock watching is `onScrollVisibilityChange(threshold: 0.33)` in the tile |
| Presentation/Media/ChatVideoSourceLoader.swift | chat_video_stream_server.dart (the player-facing half: `AVAssetResourceLoaderDelegate` over a `ChatVideoByteSource`) |
| Presentation/Media/ChatFloatingVideo.swift | chat_floating_video.dart |
| Presentation/Settings/ChatStylePicker.swift | chat_appearance_settings.dart (`_StyleCard`), chat_style_preview.dart |
| Presentation/Settings/ChatWallpaperPicker.swift | chat_wallpaper_picker.dart |
| Presentation/Settings/ChatWallpaperColors.swift | chat_wallpaper_colors.dart |
| Presentation/Settings/ChatWallpaperCustomColor.swift | chat_wallpaper_custom_color.dart |
| Presentation/Shell/ChatInfoStorageCard.swift | chat_info_storage_card.dart |
| Presentation/Shell/ForwardChatRow.swift | forward_chat_row.dart |
| Presentation/Shell/ForwardMessageDialog.swift | forward_message_dialog.dart |
| Presentation/Shell/ForwardTargets.swift | forward_message_dialog.dart (`_targets`) |
| Presentation/Storage/ChatStorageKinds.swift | chat_storage_bar.dart (`chatStorageKinds`, `ChatStorageBar`, `ChatStorageLegend`) |
| Presentation/Storage/ChatStorageMeter.swift | chat_storage_meter.dart |
| Presentation/Storage/ChatStorageModel.swift | providers (`chatCacheUsageProvider`) + chat_storage_panel.dart (clear) |
| Presentation/Storage/ChatStoragePanel.swift | chat_storage_panel.dart |
| Presentation/Storage/ChatStorageRows.swift | chat_storage_rows.dart |
| Presentation/Stickers/StickerImportErrors.swift | import_sticker_pack_dialog.dart (failure switch) |
| Presentation/Style/ChatWallpaperPreview.swift | providers (`chatWallpaperPreviewProvider`, `shownChatWallpaperProvider`) |
| Presentation/Thread/MergeRequestFreshness.swift | providers/merge_request_providers.dart (`_kFresh`, refetch on resume) |

Files without a one-to-one Dart source (Swift-only glue): `ChatFeature.swift`, `Module.swift`, `Support/JSONParser.swift`, `Support/JSONValue.swift`, `Support/RX.swift`, `Data/Xxd/ApiSchemeCodec+Coding.swift`, `Data/Xxd/XxdHTTPTransport.swift`, `Data/Repositories/XxdChatRepository+Actions.swift`, `Data/Repositories/XxdChatRepository+Reads.swift`, `Data/Local/ChatLocalDatasource+Messages.swift`, `Data/Local/ChatRows.swift`, `Data/Support/AsyncStreamExtras.swift`, `Data/Support/Broadcast.swift`, `Domain/UseCases/RepositoryPassthroughUseCases.swift`, `Domain/ValueObjects/ChatCancelToken.swift`, `Domain/ValueObjects/ChatEmojiTables.swift`, `Presentation/ChatServices.swift`, `Presentation/Shell/ChatThreadState.swift`

## Deviations from the Dart implementation

- **No Quill delta**: the composer is a plain/Markdown text view (`MarkdownFormatter`); `BuildMessageText` (delta → Markdown) has no Swift counterpart.
- **JSON model**: xxd packets are `JSONValue` (order-preserving, `undefined` vs `null` kept for `ApiSchemeCodec`) instead of `Map<String,Object?>`.
- **Transport**: `URLSessionWebSocketTask` + `XxdTLSPolicy` (TOFU SHA-256 pinning in the URLSession delegate); uploads go through
  `uploadTask(fromFile:)` (the system chunks the body; progress from `didSendBodyData`) instead of hand-written 64 KB writes.
- **Video**: no localhost proxy (`chat_video_stream_server`): `AVAssetResourceLoader` (`ChatVideoSourceLoader`) turns every byte-range request AVFoundation makes into one pinned-TLS ranged GET (`XxdRangeStream` through `UpstreamVideoSource`), so playback starts before the download ends and seeks to the index at the end of a phone recording. A first pass from the first byte to the last is recorded and moved into the file cache (a video played once is cached). Without a known size or an online session it falls back to downloading the whole file first (`ChatRepository.videoPlayback`).
- **Video tile / viewer**: the tile plays in its frame, floats as a mini player when scrolled out of view (one video per open chat; leaving the chat stops it); the viewer sheet has the controls bar and the keys Space, ←/→, M, L, F, Esc. "F" toggles the main window's full screen (the sheet has no window of its own to enlarge).
- **Playback priority** (`MediaPlaybackPriority`) is not ported: background downloads do not yield to a playing video.
- **Animated stickers**: `.tgs` plays through Lottie, but import cannot convert it to animated WebP (ImageIO has no WebP encoder, and the
  tgs bytes themselves are no use to the other clients a sticker is sent to): imports fall back to the still thumbnail; stills are stored as PNG instead of WebP.
- **Row cache** (`ChatRowCache`): not needed — rows are mapped inside the GRDB observation and de-duplicated with `removingDuplicates()`.
- **ZenTao profile table**: the account name for xxd sign-in is `Account.handle` (no `zenTaoProfiles` table in the Swift core schema).
- **Table names** are camelCase (`chatMessages`, …) like the other Swift core tables; the module's migration id is `chat_v1`.
- **Translation**: `TranslateChatMessage` takes a `ChatTextTranslator` protocol (the app adapts `FeatureTranslation`'s service) because features do not import each other.
- **Merge-request cards**: the app implements `MergeRequestLinkService` (`MergeRequestLinkFetcher` in `App/Sources/ChatWiring.swift`) over the pooled adapter of `AccountSyncService`; the +/− lines and file count of a GitLab MR show only when the adapter already reports them (the Swift core has no `RepoChangesAdapter` to ask for the diff).
- **Notifications**: the open chat is reported by the view (`ChatShellEvents.openChat`, set by `ChatShellModel.select/start/stop`); the bridge's `visibleChat` returns it only while the Chat place is on screen, so only that chat's notification is dropped.
- **Cache clear**: after a chat-section clear in the Local-data page the app signs every chat account out and in again (`ChatWiring.reconnectAll`, `reload_after_cache_clear.dart`); clearing downloaded files (`ChatStoragePanel`) only reloads the usage.
- **Chat storage / wallpaper / style pickers** are public views (`ChatStoragePanel`, `ChatWallpaperPicker`, `ChatStylePicker`) that read `\.chatServices` / `\.chatSettings`; the settings pages in the app host them and save what they report. The wallpaper colour preview is `ChatWallpaperPreview.shared` (the background follows a drag, saved 400 ms after it pauses).
- **New shared widget**: `CoreUI/Widgets/Fields/HsvColorFields.swift` (`HsvColor`, `HsvSaturationValueArea`, `HsvHueBar`, `AppSwatchButton`).
- **Person chips**: `ChatPersonChip` opens the one-to-one chat (through `ChatServices.showChat`, which the app wires to the Chat place); `ChatPersonChatButton` / `ChatPersonAvatar` are injected as `\.zentaoDocPersonAction` / `\.zentaoDocPersonFace` in `HostWiring`.
- **Translation gate**: `ChatServices.ensureTranslatorReady` (the app's `OpenCodeLinkGate`) runs before a message is translated.
- **Not ported**: the image viewer's strip lists photos only (the Dart strip also lists videos); the OpenCode key field gains a "Remove key" button (absent in the Dart field) backed by `OpenCodeKeyRepository.removeApiKey`.

### macOS-only: tickets from messages and multiple select (not in the Flutter app)

Mirrors the message menu of ZenTao's own desktop client.

- **Create bug / Create task / Create todo** (`Thread/MessageActions.swift`, domain `DraftTicketFromMessages`, `Thread/ChatMessageExport.swift`): offered on a message with text or code when the host sets `ChatShellEvents.onCreateTicket`. The message's first line becomes the title; the body quotes the message and says which chat and who it came from. The app (`ChatWiring`) opens the full bug / task editor filled in (`AppNavController.openEditor(_:prefill:)` → `TicketEditorPrefill`, laid over ZenTao's form above its steps template), or the "New todo" dialog (`ToolZenTao/Presentation/Widgets/ZentaoTodoDialog.swift`).
- **Select multiple** (`ChatThreadState.selection`, `Thread/MessageSelectionRow.swift`, `Shell/ChatSelectionBar.swift`): a click picks or drops a row; the bar in the composer's place copies the picked messages as one transcript, forwards them (oldest first, `ChatForwardRequest`), or starts a bug / task / todo quoting all of them. Esc or ✕ leaves.
- **Todo** (`ZenTaoTodos` ← `ZenTaoTodoService`, `CreateZenTaoTodo`): `POST /api.php/v1/todos` as a plain all-day todo of the signed-in user. **Unverified against a real server.**

### macOS-only: paste, drop and the picture viewer

- **Paste**: the composer's plain-text `NSTextView` enabled Paste only for text, so ⌘V with a screenshot (an image alone) on the clipboard did nothing. `ComposerNSTextView.validateMenuItem` / `validateUserInterfaceItem` now enable it whenever the clipboard holds files or an image (`PasteboardKit.hasAttachments`); pictures in other formats (JPEG, HEIC, PDF) are read too when the clipboard holds no text.
- **Drop** (`Composer/ChatFileDrop.swift`): files and pictures dropped anywhere on the messages or the input wait in the input; a picture with no file behind it (a browser image, the screenshot thumbnail) is sent as PNG, JPEG, GIF or WebP as it came, anything else as PNG. Not in a read-only chat or during "Multiple select".
- **Viewer** (`Media/ChatImageViewer*.swift`, `ChatViewerSize`): picture and video viewers open at 92 % of the window (720×520 to 2200×1500); the bar shows place, pixel size and file size, zoom as a percentage, the rarer actions under "…"; previous / next are large arrows at the picture's sides; the strip is part of the dark stage.
