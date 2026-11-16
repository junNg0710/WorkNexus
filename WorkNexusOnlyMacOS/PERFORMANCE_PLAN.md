# Plan: tối ưu performance app và làm nhân vật TBChat di chuyển mượt

Trạng thái (2026-11-17): **đã làm bước 1, 2, 3** của bảng cuối file; bước 0 (đo bằng Instruments), 4, 5, 6 **chưa làm**.

Đã làm:
- Bước 1: board ZenTao tính một lần cho mỗi thay đổi (`ZentaoBoardCache`, `BoardController.revision`); mỗi ticket chỉ parse deadline một lần cho mọi chip/đếm/workload (`ZenTaoLeaderFacts`). Test: 20 lần vẽ lại = 4 lần tính; đếm 5 000 ticket < 0,5 s.
- Bước 2: nhân vật — vị trí là hàm theo thời gian có ease-in/out, đọc theo nhịp màn hình (`TimelineView(.animation)`, chỉ chạy khi đang đi); sprite là một `CALayer` đổi `contentsRect`; tốc độ theo pt/giây (90) không theo bề rộng cửa sổ; dừng hẳn khi cửa sổ không nhìn thấy. Chưa làm: đồng bộ bước chân (6.4), quán tính khi thả (6.5), tuỳ chọn cỡ (6.7).
- Bước 3: board của section đang ẩn không tính lại (`BoardController.isActive`), đọc badge Dock và khung nhân vật dừng khi cửa sổ ẩn.

Chưa đo bằng Instruments trên app thật: các con số ở trên là từ unit test, không phải số đo trong app. Các con số "đã đếm" là đọc từ code ngày 2026-11-17; mọi nhận định về độ chậm là **giả thuyết cho tới khi đo** (bước 0).

## 0. Đo trước (bắt buộc, làm đầu tiên)

Không tối ưu theo cảm giác. Lấy số nền để biết cái gì thật sự chậm và để so sau khi sửa.

- Instruments trên bản Release: **Time Profiler**, **SwiftUI** (view body / update count), **Hangs**, **Allocations**.
- Kịch bản đo (ghi lại số cho từng cái): mở app tới lúc dùng được; chuyển Tasks ↔ Bugs ↔ Chat; mở board 892 task (execution `VN_Daily_Tasks`); bấm một chip lọc; gõ vào ô lọc; cuộn list; mở chi tiết ticket; để app nền 10 phút (CPU khi idle); nhân vật đi bộ.
- Thêm `os_signpost` quanh: `BoardController.recompute`, `ZentaoBoards.taskBoard/bugBoard`, `GRDBTicketRepository.upsertTickets`, decode `TicketRow.entity`.
- Tiêu chí đạt: không có hang > 100 ms khi bấm chip/đổi tab; CPU idle < 1–2 % khi không tương tác; nhân vật không rớt khung khi đi.

## 1. Dữ liệu ticket: đọc và decode quá nhiều (nghi ngờ lớn nhất)

Đã đếm trong code:
- `watchTickets()` có **11 nơi đăng ký**. Mỗi lần bảng `tickets` đổi, mỗi nơi nhận lại **toàn bộ** hàng và decode `providerEntityJson` (JSON) cho từng hàng (`GRDBTicketRepository.watchTickets` → `TicketRow.entity`).
- `BoardController` (2 cái cho ZenTao: task, bug) gọi `recompute()` mỗi lần `tickets`/`accounts`/`filter` đổi: scope + `BuildBoard` trên toàn bộ.

Việc cần làm:
1. **Một nguồn ticket dùng chung**: một `TicketStore` (actor/@Observable) giữ snapshot đã decode, các nơi khác đọc từ đó thay vì mỗi nơi tự `ValueObservation`. Decode một lần cho mỗi thay đổi.
2. **Decode tăng dần**: giữ cache `id → (rowVersion, Ticket)`; chỉ decode hàng có nội dung đổi (so `providerEntityJson`/`updatedAt`), không decode lại 100 % sau mỗi lần upsert một trang.
3. **Truy vấn theo phạm vi**: board chỉ cần ticket của một account + loại + execution/product. Thêm cột/chỉ mục (`accountId` đã có; thêm `externalType`, và bảng phụ `ticketMemberships(ticketId, label)` thay cho lọc nhãn trong bộ nhớ) rồi `watchTickets(scope:)`.
4. **Gộp ghi**: một trang 50–100 ticket = một transaction (đã vậy) nhưng "Load all" và đọc theo nhóm ghi nhiều trang liên tiếp → debounce thông báo (GRDB `ValueObservation` với `scheduling`/throttle ~100 ms) để UI không tính lại sau từng trang.

## 2. Board ZenTao: tính lại cùng một thứ nhiều lần mỗi lần vẽ

Đã đếm: `ZentaoBoards.taskBoard/bugBoard/taskTable/bugTable/bugShownCount` được gọi ở **7 chỗ** trong view; thanh leader gọi thêm `workload`, `quickCounts`, `leaderPool`, `shownTickets` (**4 chỗ**). Mỗi lần gọi là chạy lại `FilterTickets` + `ApplyLeaderFilter` + sắp xếp trên toàn bộ ticket trong scope; `quickCounts` duyệt 8 chip × N ticket, mỗi lần lại parse deadline.

Việc cần làm:
1. **Memo theo phiên bản**: trong `ZentaoUIState` giữ `boardRevision` (tăng khi scoped/filter/leader/sort đổi) và cache kết quả `taskBoard`, `bugBoard`, `leaderPool`, `workload`, `quickCounts` theo revision. View chỉ đọc cache.
2. **Tính trước deadline**: parse `deadline` một lần khi decode ticket (lưu `Date?` trong cache phụ theo id), không parse trong vòng lọc.
3. **Một lượt duyệt cho các chip**: `CountQuickFilters` duyệt N một lần, tính cả 8 chip.
4. **Tách phạm vi vẽ lại**: `ZentaoBoardCard` nhận giá trị (ticket, selected, pending) thay vì đọc `controller` @Observable → chỉ thẻ đổi mới vẽ lại. Kiểm bằng Instruments SwiftUI.
5. Cột dài: đã `LazyVStack`? Kiểm `BoardColumnFrame`; nếu không lazy thì đổi, và giới hạn số thẻ vẽ ban đầu.
6. Tính board ngoài main actor khi N lớn (> ~2000): chạy filter/sort trong `Task.detached`, áp kết quả theo revision.

## 3. Màn hình giữ sống (KeepAlive) và công việc nền

- `Viewport.keepAliveLimit = 5`: 5 section và 5 pane vẫn mount khi ẩn. Chúng vẫn nhận thay đổi ticket và tính lại.
  → Thêm cờ `sectionIsActive` (đã có trong env) để **bỏ qua recompute khi ẩn**, tính lại một lần khi hiện.
- Polling đang có: badge Dock mỗi 4 s (mới thêm), khung nhân vật, đồng bộ chat/ticket, `SessionCookieKeeper`.
  → Dừng mọi polling khi cửa sổ ẩn/thu nhỏ (`NSWindow.occlusionState`, `NSApplication.didResignActive`), chạy lại khi hiện.
- Mini app: mỗi tab là một web process; giới hạn `liveLimit` đã có. Tab nền đã lazy (mới thêm). Cân nhắc "ngủ" tab không dùng > 15 phút.

## 4. Chat

Cần đo trước; các điểm nghi ngờ: decode ảnh/sticker trên main (`NSImage(data:)`), sticker động chạy cả khi khuất (đã dừng khi view rời cửa sổ, nhưng trong `LazyVStack` thẻ khuất chưa chắc bị gỡ), Markdown/mention parse lại mỗi lần vẽ.
- Decode ảnh ngoài main + downsample theo kích thước hiển thị (đã có cho ảnh thường, chưa có cho sticker).
- Cache kết quả parse Markdown theo `message.gid + sửa đổi`.
- Dừng `FramePlayerView` khi không nằm trong vùng nhìn thấy của scroll (dùng `onScrollTargetVisibilityChange` đã có).

## 5. Khởi động

Đo `CompositionRoot.start()` và thời gian tới khung hình đầu. Hoãn: quét app đã cài, đọc cookie/mật khẩu, kiểm tra cập nhật, mở web view đầu tiên → sau khi cửa sổ đã hiện.

## 6. Nhân vật TBChat mượt hơn

Hiện trạng (đọc code `CoreUI/Widgets/Pet`):
- `PetView` chạy vòng `Task.sleep(frameDuration)` rồi `director.tick()`. **Vị trí chỉ đổi mỗi tick**, mà tick = thời lượng một khung sprite: 0,09 s khi chạy (≈ 11 bước/giây), 0,32 s khi đứng. Vì vậy đi bộ trông giật từng nấc.
- Mỗi tick đổi `@Observable` → vẽ lại cả lớp phủ; ảnh 192×208 được SwiftUI co về 84 pt mỗi khung với `.interpolation(.high)`.
- Vòng lặp chạy cả khi cửa sổ ẩn.

Thiết kế mới:
1. **Tách hai nhịp**: khung sprite đổi theo `frameDuration` của animation; **vị trí nội suy theo đồng hồ màn hình** (60/120 Hz) bằng `TimelineView(.animation)` hoặc `CADisplayLink` của `NSView` — vị trí = hàm của thời gian, không phải cộng dồn mỗi tick.
2. **Vẽ bằng Core Animation**: một `CALayer` có `contents` = atlas và đổi `contentsRect` theo khung (GPU, không decode/scale lại), `magnificationFilter = .nearest`/`.trilinear` tuỳ nhìn đẹp; di chuyển bằng `position` của layer. Không đi qua SwiftUI mỗi khung.
3. **Chuyển động có gia tốc**: ease-in/ease-out khi bắt đầu và dừng, tốc độ theo pt/giây (không theo tỉ lệ chiều rộng cửa sổ như hiện tại — cửa sổ rộng thì đi nhanh bất thường), lật hướng đúng lúc đổi chiều, khung "đứng" chèn 1 nhịp trước khi chuyển sang chạy.
4. **Đồng bộ bước chân**: quãng đường mỗi khung chạy = bước chân của sprite (đo từ sheet) để chân không trượt trên nền.
5. **Kéo thả**: bám chuột trực tiếp theo layer, thả ra có quán tính nhẹ rồi rơi xuống đáy.
6. **Tiết kiệm**: dừng hẳn khi cửa sổ bị che/thu nhỏ/app nền, khi "Reduce Motion", và khi nhân vật đứng yên thì chỉ chạy timer chậm cho chớp mắt.
7. Tuỳ chọn trong Settings: cỡ nhân vật (S/M/L), cho phép đi lại hay đứng yên.

Kiểm chứng: test cho hàm vị trí theo thời gian (đều, không nhảy, dừng đúng đích); Instruments đo CPU khi đứng (< 0,5 %) và khi đi; quay màn hình 120 Hz kiểm không giật.

## Thứ tự đề xuất

| Bước | Việc | Rủi ro | Lợi ích dự kiến |
|---|---|---|---|
| 0 | Đo + signpost | thấp | biết đúng chỗ chậm |
| 1 | Memo board theo revision (mục 2.1–2.3) | thấp | bấm chip/gõ lọc nhanh hẳn |
| 2 | Nhân vật: nội suy vị trí + CALayer (mục 6.1–6.3, 6.6) | thấp | mượt thấy ngay |
| 3 | Bỏ recompute khi section ẩn + dừng polling khi cửa sổ ẩn (mục 3) | thấp | giảm CPU nền |
| 4 | Một nguồn ticket + decode tăng dần (mục 1.1–1.2) | vừa | giảm giật khi đồng bộ |
| 5 | Truy vấn theo phạm vi + chỉ mục (mục 1.3) | cao (đổi schema) | cần khi dữ liệu > vài nghìn ticket |
| 6 | Chat + khởi động (mục 4, 5) | vừa | theo số đo |

Mỗi bước: đo trước/sau cùng kịch bản, giữ toàn bộ test, không đổi hành vi.
