# Falemag: ý tưởng cốt lõi (bản phác 2)

> Trạng thái: bản nháp để bàn. Bản 2 thêm mục 8: năm hướng phá cách và một hướng ghép
> được đề xuất ("Ấn Truyền"). Các mục 3–7 giữ làm phương án an toàn để so sánh. Mọi tên riêng (thế giới, tộc, nhân vật) là tên tạm,
> tự đặt cho dự án, không lấy từ game có sẵn.

## 1. Mong muốn của Phúc và giới hạn kỹ thuật

| Mong muốn | Giới hạn |
|---|---|
| Thời phong kiến nhưng kỳ ảo, không hiện thực | Game 2D nhẹ, chạy tốt trên máy yếu và điện thoại |
| Thế giới nhiều chủng tộc | Godot 4.7.x, gameplay viết bằng C++ (GDExtension) |
| Xung đột, mất mát, phản bội; nhân văn; nhân quả | Có thể chơi qua mạng |
| Lối chơi chiến thuật, sinh tồn, auto chess | Giọng nói sinh từ TTS tts.falevon.com |
| Nhân vật càng nhiều càng tốt, không giới hạn kiểu cách | Tập trung vào cốt truyện và tính chiến thuật |

Từ đó rút ra ba trụ cột thiết kế, dùng để chấm mọi tính năng về sau:

1. **Mỗi lựa chọn đều có quả.** Người chơi luôn truy được "vì sao chuyện này xảy ra".
2. **Mất mát có ý nghĩa.** Nhân vật chết là chết thật, nhưng để lại dấu vết trong thế giới.
3. **Chiến thuật trước trận, không phải phản xạ trong trận.** Hợp điện thoại, hợp máy yếu, hợp chơi mạng.

## 2. Thế giới chung (dùng cho cả ba phương án)

**Đại lục Hằng Khư**, chín châu dưới một ngai vàng. Ba trăm năm trước, Thiên Triều dùng
cấm thuật **Thiên Mệnh Ấn** buộc vận mệnh mọi tộc vào long mạch của ngai vàng: tộc nào
quy phục thì được mùa, tộc nào chống lại thì mất mùa, dịch bệnh. Hòa bình có thật,
nhưng là hòa bình của sợi xích.

Mười năm trước, trong **Đêm Nguyệt Liệt**, Ấn bị phá từ bên trong: một đại thần phản bội
Hoàng đế ngay giữa lễ tế. Mặt trăng nứt làm đôi. Mọi món nợ nhân quả từng bị Ấn đè xuống
bung ra cùng lúc. Người chết mà nghiệp chưa trả không siêu thoát được. Các tộc tranh nhau
phần đất màu mỡ còn lại. Chín châu thành loạn thế.

### Các tộc (bản đầu, mở rộng được)

| Tộc | Nét riêng | Vai trò trong truyện |
|---|---|---|
| **Nhân** | Đông nhất, chia phe triều đình, phiên trấn, nghĩa quân | Bên gây ra và bên chịu Thiên Mệnh Ấn |
| **Thạch Duệ** | Sinh ra từ đá núi, sống hàng trăm năm, chậm và nhớ dai | Giữ ký ức, biết sự thật về Ấn |
| **Vũ Dân** | Có cánh, sống trên vách đá, giỏi đưa tin và cung | Bị triều đình dùng làm mật thám, mang tiếng phản trắc |
| **Lân Thủy** | Có vảy, sống ven sông biển, buôn bán, theo mẫu hệ | Nắm lương thực, kẻ có lợi nhất khi loạn |
| **Mộc Hồn** | Linh thể của rừng già, mượn thân gỗ | Rừng bị đốt để mở ruộng, mang hận cũ |
| **Lang Tộc** | Thú nhân du mục thảo nguyên, trọng lời thề | Vừa là kẻ thù vừa là đồng minh tốt nhất |
| **Vong Nhân** | Người chết chưa trả hết nghiệp, không đi được | Hiện thân của nhân quả dang dở |

Không tộc nào là phe ác. Mỗi tộc có lý do chính đáng và có tội riêng.

## 3. Ba phương án

### Phương án A: "Đoàn Lưu Vong" (đề xuất)

**Một câu:** dẫn một đoàn người lưu vong băng qua chín châu loạn lạc; ban ngày lo cái ăn
và lòng người, khi gặp địch thì xếp quân trên bàn cờ và để trận đánh tự diễn ra.

**Vòng lặp chơi**

```
Bản đồ châu (chọn đường đi, từng nút)
  -> Sự kiện / Trận đánh / Thành trấn / Chỗ nghỉ
     -> Trận: xếp quân trên bàn cờ, trận tự đánh (auto chess)
     -> Sự kiện: lựa chọn có gieo "nhân"
  -> Hạ trại cuối mỗi chặng (sinh tồn: chia lương, gác đêm, chữa thương, trò chuyện)
  -> Mùa đổi, "nhân" cũ chín thành "quả"
  -> Sang chặng kế tiếp; hết một châu thì sang hồi truyện mới
```

- **Vòng ngắn (3–8 phút):** một trận hoặc một sự kiện. Hợp điện thoại, chơi lúc rảnh.
- **Vòng trung (30–60 phút):** một châu, kết thúc bằng trận trùm và một "quả" lớn.
- **Vòng dài:** cả chiến dịch, nhiều kết thúc tùy sổ nhân quả; chơi lại thì đi đường khác, gặp nhân vật khác.

**Cốt truyện chính**

Người chơi là **Ký**, người chép sử trẻ của một gia tộc nhỏ phụ trách ghi sổ lễ tế. Đêm
Nguyệt Liệt, cả nhà Ký bị thảm sát vì bị vu là kẻ phá Ấn. Người mở cổng cho sát thủ là
**Diên**, anh em kết nghĩa của Ký. Ký sống sót, mang theo cuốn **Sổ Nhân Quả** của tổ tiên:
cuốn sổ cho người giữ nó nhìn thấy sợi dây nối giữa việc đã làm và chuyện sẽ đến.

- **Hồi 1, Lưu vong:** gom người sống sót từ nhiều tộc thành một đoàn, chỉ để sống qua mùa đông.
- **Hồi 2, Truy tìm:** lần theo Diên, phát hiện Diên phản vì em gái bị triều đình giữ làm con tin. Kẻ phản bội cũng là nạn nhân.
- **Hồi 3, Sự thật:** người Thạch Duệ hé lộ rằng chính tổ tiên Ký đã chép Thiên Mệnh Ấn vào sổ. Gia tộc Ký không vô tội.
- **Hồi 4, Lựa chọn:** đến kinh đô. Dựng lại Ấn để chấm dứt loạn (đổi lấy xiềng xích), phá hẳn Ấn để mọi tộc tự trả nghiệp (đổi lấy thêm máu), hoặc gánh nghiệp thay (đổi lấy chính mình và những người đi theo).

Kết thúc không chọn bằng một nút bấm cuối game. Nó mở ra hay khóa lại tùy những gì đã
ghi trong sổ suốt hành trình: ai còn sống, ai còn tin Ký, Ký đã tha ai, giết ai, hứa gì.

**Vì sao chọn phương án này:** gói trọn cả ba lối chơi Phúc thích vào một vòng lặp gọn,
cốt truyện có chỗ đứng ở mọi bước, và trận auto chess vừa nhẹ máy vừa dễ đưa lên mạng.

### Phương án B: "Thành Cuối"

**Một câu:** giữ một thành trì cuối cùng giữa loạn thế; ngày xây dựng và phân chia tài
nguyên, đêm quân địch kéo đến theo đợt và trận phòng thủ tự diễn ra trên bàn cờ.

- **Vòng lặp:** ngày (giao việc, xây, buôn bán, đón dân tị nạn) -> đêm (xếp quân giữ thành, auto chess phòng thủ theo đợt) -> sáng (đếm tổn thất, xử chuyện trong thành).
- **Cốt truyện:** người chơi là thành chủ bất đắc dĩ. Dân tị nạn từ nhiều tộc đổ về, mang theo thù cũ. Phản bội đến từ bên trong tường thành.
- **Mạnh:** sinh tồn sâu nhất, nhân quả hiện rõ ngay trong thành (cứu ai, đuổi ai).
- **Yếu:** giao diện xây dựng nặng trên điện thoại, thế giới chỉ thấy qua lời kể, ít chỗ cho "rất nhiều nhân vật" xuất hiện tự nhiên.

### Phương án C: "Bàn Cờ Thiên Mệnh"

**Một câu:** game chiến thuật theo lượt cổ điển, điều khiển từng quân trên bản đồ ô, truyện tuyến tính chia chương.

- **Vòng lặp:** hội thoại -> trận chiến thuật theo lượt -> doanh trại (nâng cấp, trò chuyện) -> chương kế.
- **Mạnh:** chiều sâu chiến thuật cao nhất, kể chuyện chặt chẽ nhất.
- **Yếu:** không có auto chess; mỗi bản đồ phải dựng tay nên tốn công nội dung; trận dài, khó chơi mạng; thao tác nhiều trên màn hình cảm ứng.

### So sánh nhanh

| Tiêu chí | A. Đoàn Lưu Vong | B. Thành Cuối | C. Bàn Cờ Thiên Mệnh |
|---|---|---|---|
| Chiến thuật | Cao (trước trận) | Trung bình | Rất cao |
| Sinh tồn | Cao | Rất cao | Thấp |
| Auto chess | Lõi | Lõi | Không |
| Chỗ cho truyện | Rất cao | Trung bình | Rất cao |
| Dàn nhân vật lớn | Rất hợp | Hợp | Hợp |
| Nhẹ máy, điện thoại | Rất hợp | Trung bình | Hợp |
| Chơi mạng | Dễ | Trung bình | Khó |
| Công làm nội dung | Trung bình | Trung bình | Cao |

**Đề xuất: phương án A**, mượn phần "hạ trại" của B làm pha sinh tồn. Phần còn lại của
tài liệu mô tả các hệ thống của A.

## 4. Hệ thống cốt lõi của phương án A

### 4.1 Sổ Nhân Quả

Không phải thanh thiện ác. Đây là một sổ ghi sự kiện, dữ liệu hóa hoàn toàn.

- Mỗi hành động quan trọng gieo một **Nhân**: `{loại, đối tượng, nơi, mùa, mức độ}`.
  Ví dụ: `tha_mạng(lính_Lang_tộc_Ba_Khắc, châu_Bắc, đông_năm_1)`.
- Mỗi **Quả** là một sự kiện có điều kiện trên các Nhân, kèm độ trễ.
  Ví dụ: "Nếu đã tha Ba Khắc và đã qua ít nhất 2 mùa, khi vào thảo nguyên thì Ba Khắc dẫn bộ tộc đến trả ơn. Nếu Ba Khắc đã bị giết thì em trai hắn đến báo thù."
- Khi Quả xảy ra, giao diện mở trang sổ cho thấy sợi dây: *"Mùa đông năm trước, ngươi đã tha cho hắn."* Đây là khoảnh khắc nhân văn mà game cần tạo ra nhiều nhất.
- Quả có thể đến từ việc rất nhỏ (chia thêm phần cơm cho đứa trẻ) và rất lâu sau.
- Viết sự kiện bằng dữ liệu, không viết bằng code, để thêm hàng trăm sự kiện mà không đụng engine.

### 4.2 Lòng tin và phản bội

Mỗi nhân vật trong đoàn có **Tin** (với Ký), **Nghĩa** (với từng người khác) và một **Vết**
(nỗi đau, tham vọng, món nợ riêng).

- Tin thấp cộng Vết bị chạm thì có thể bỏ đoàn, lấy trộm lương, hoặc trở giáo giữa trận.
- Phản bội luôn có dấu hiệu báo trước trong hội thoại và trong sổ, để người chơi thấy mình có thể đã ngăn được.
- Người chơi cũng có thể phản bội: bỏ người bị thương lại, bán đồng đội cho phe khác, thất hứa. Sổ ghi hết.

### 4.3 Mất mát

- Nhân vật tử trận thì chết hẳn (có tùy chọn dễ cho người chỉ muốn đọc truyện).
- Người chết để lại **di vật** (trang bị mang ký ức, có hiệu ứng nhỏ) và có thể thành Vong Nhân nếu còn nợ nghiệp, gặp lại về sau.
- Mỗi lần hạ trại có thể dựng mộ, nói lời tiễn. Người thân của họ trong đoàn phản ứng theo.

### 4.4 Sinh tồn (pha hạ trại)

Bốn tài nguyên: **Lương**, **Thuốc**, **Củi** (mùa lạnh), **Khí thế** (tinh thần chung).

- Mỗi đêm giao việc: ai đi kiếm ăn, ai gác, ai chữa thương, ai nghỉ. Thiếu gác thì có thể bị đánh úp; thiếu lương thì phải quyết ai nhịn.
- Mùa thay đổi luật chơi: đông thiếu ăn và lạnh, xuân dịch bệnh, hạ hạn hán, thu loạn quân.
- Trò chuyện bên lửa trại là nơi mở khóa truyện riêng của từng nhân vật và tăng Nghĩa.

### 4.5 Trận đánh auto chess

- **Bàn cờ** 7 cột x 4 hàng mỗi bên (vừa màn hình dọc lẫn ngang). Trước trận xếp quân, chọn trận pháp, dùng tối đa 1 mưu kế; sau đó trận tự diễn ra 30–60 giây.
- **Đồng bộ tộc** (ví dụ 2/4 Lang Tộc: hồi máu khi hạ địch) và **đồng bộ đạo**: Kiếm, Thương, Cung, Thuật, Thủ, Y, Mưu, Ám.
- **Tình nghĩa trên bàn cờ:** hai người kết nghĩa đứng cạnh nhau thì mạnh thêm; hai kẻ thù đứng cạnh nhau thì có thể không chịu phối hợp. Quan hệ ngoài truyện ảnh hưởng thẳng vào chiến thuật.
- **Hai loại quân:** *danh tướng* (có tên, có truyện, độc nhất, lên cấp bằng trải nghiệm và di vật) và *binh tốt* (chiêu mộ ở thành trấn, ghép 3 thành 1 để lên sao như auto chess quen thuộc).
- Trận chạy bằng mô phỏng tất định (cùng đầu vào, cùng kết quả). Đây là nền cho chơi mạng ở mục 6.

### 4.6 Dàn nhân vật mở rộng theo dữ liệu

Mục tiêu: thêm nhân vật mới chỉ cần thêm file dữ liệu, hình và giọng, không sửa code.

Một nhân vật gồm:

```
CharacterDef
  id, tên, tộc, đạo (1–2), độ hiếm
  chỉ số gốc, kỹ năng (ghép từ các "mảnh hiệu ứng" có sẵn)
  quan hệ mặc định: kết nghĩa / thù / nợ với id khác
  Vết, điều kiện phản bội
  móc nhân quả: Nhân nào gieo khi chiêu mộ, khi chết, khi bị bỏ rơi
  hội thoại lửa trại, câu thoại trận (khóa TTS)
  chân dung + bộ sprite trận
```

- Kỹ năng ghép từ các khối viết bằng C++: gây sát thương, hồi máu, trạng thái, triệu hồi, đẩy lùi, đổi chỗ, khiêu khích, lan, theo điều kiện. Thiết kế viên tổ hợp khối thành kỹ năng mới trong file dữ liệu.
- "Không giới hạn kiểu cách": **chân dung** hội thoại được tự do phong cách theo từng nhân vật; **sprite trận** giữ chung một khung (kích thước, góc nhìn, số khung hình) để bàn cờ dễ đọc và nhẹ.
- Mục tiêu nội dung: bản thử 20 nhân vật, bản đầy đủ 120+, sau đó cập nhật theo mùa.

## 5. Kỹ thuật cho máy yếu và điện thoại

- Renderer GL Compatibility (repo đang dùng), 2D thuần, sprite atlas, không shader nặng.
- Sprite trận nhỏ (khoảng 64 px), hoạt ảnh 4–6 khung; chân dung tải theo nhu cầu.
- Logic trận viết bằng C++ GDExtension, chạy tick cố định (khoảng 15 tick/giây), dùng số nguyên hoặc fixed-point, RNG có seed. Phần hiển thị chỉ đọc trạng thái mô phỏng và nội suy.
- UI và kịch bản sự kiện dùng scene Godot và file dữ liệu; GDScript chỉ làm keo nối.
- Mục tiêu hiệu năng: 60 fps trên máy tích hợp đồ họa cũ, 30 fps ổn định trên điện thoại tầm thấp, bản cài dưới 300 MB.

### Giọng nói (TTS)

- Sinh trước khi build bằng tts.falevon.com, đóng gói thành file ogg; không gọi TTS lúc chơi, nên chơi offline được và không tốn mạng.
- Mỗi câu thoại có khóa; một công cụ build đọc toàn bộ khóa trong dữ liệu nhân vật, sinh phần còn thiếu, lưu bộ nhớ đệm theo nội dung câu.
- Ưu tiên lồng tiếng cho khoảnh khắc lớn (Quả, tử trận, phản bội) và câu thoại ngắn trong trận; hội thoại dài có thể chỉ có chữ.

## 6. Chơi qua mạng

Đi theo hai bước để không làm nặng bản đầu:

1. **Đấu bóng (bất đồng bộ):** gửi ảnh chụp đội hình lên máy chủ, đánh với đội hình của người khác. Vì mô phỏng tất định, máy chủ chỉ cần lưu đội hình và seed, có thể tự chạy lại để chống gian lận. Máy chủ rất nhẹ.
2. **Loạn Thế Hội (thời gian thực, sau này):** chế độ riêng 2–8 người, kho quân chung, mua bán xếp quân như auto chess cổ điển, dùng chung dàn nhân vật và đồng bộ của chiến dịch. Đồng bộ kiểu lockstep: chỉ gửi lệnh xếp quân, không gửi trạng thái trận.

Cốt truyện chiến dịch giữ chơi một người; có thể cân nhắc cho bạn bè "gửi một danh tướng đi giúp" như một kiểu hợp tác nhẹ.

## 7. Bản thử đầu tiên (vertical slice)

Đủ để biết game có vui không:

- 1 châu (Hồi 1), khoảng 12 nút trên bản đồ, 1 trận trùm.
- 3 tộc (Nhân, Lang Tộc, Thạch Duệ), 4 đạo, 20 nhân vật (8 danh tướng, 12 binh tốt).
- Sổ Nhân Quả với khoảng 30 Nhân và 10 Quả, ít nhất 1 phản bội có thể xảy ra.
- Hạ trại với 4 tài nguyên và 1 mùa đông.
- Mô phỏng trận C++ tất định có test, chạy được trên Windows và Android.
- Chưa làm mạng; chỉ giữ mô phỏng tất định để sẵn đường.

Thứ tự làm đề xuất: mô phỏng trận C++ -> bàn cờ và xếp quân -> định dạng dữ liệu nhân vật
-> Sổ Nhân Quả và sự kiện -> hạ trại -> bản đồ châu -> TTS pipeline.

## 8. Các hướng phá cách (bản 2)

Ba phương án ở mục 3 đều là "chỉ huy một nhóm người qua chiến tranh". Phần này bỏ giả
định đó. Mỗi hướng dưới đây đổi một thứ căn bản: người chơi là ai, thời gian chảy thế
nào, hay nhân quả đi xa tới đâu. Tất cả vẫn giữ: phong kiến kỳ ảo, nhiều tộc, auto chess
làm lõi chiến đấu, 2D nhẹ, mô phỏng trận C++ tất định.

### 8.1 "Ấn Truyền": người chơi là lời nguyền, không phải con người

Người chơi **là Thiên Mệnh Ấn**, một mảnh ấn vỡ có ý thức. Ấn sống bằng cách bám vào một
người cầm giữ và cho họ sức mạnh. Khi người cầm chết, Ấn **chuyển sang kẻ đã giết họ**
hoặc người gần nhất chạm vào nó.

- **Không có nhân vật chính.** Mỗi đời chủ là một nhân vật khác: tướng quân Nhân tộc, cô bé Lân Thủy bán cá, sư cụ Thạch Duệ, tên sát thủ Vũ Dân. Dàn nhân vật vô hạn trở thành cách kể chuyện chứ không chỉ là bộ sưu tập.
- **Phản bội là cơ chế di chuyển.** Muốn đến kinh đô? Khiến cận vệ của chủ hiện tại nổi lòng tham và đâm sau lưng chủ, Ấn sẽ sang tay cận vệ. Người chơi phải tự hỏi: mình có đang gieo phản bội chỉ để đi đường tắt?
- **Mất mát đổi nghĩa.** Chủ cũ chết rồi nhưng họ nhớ mình bị Ấn bỏ rơi. Họ có thể quay lại thành Vong Nhân trên bàn cờ, đứng phía đối diện.
- **Nhân quả:** mỗi chủ để lại một "vết ấn" (ơn, oán, lời hứa chưa giữ). Người kế tiếp phải gánh. Ấn không chết, nên nó gánh hết nghiệp của mọi đời chủ.
- **Auto chess:** quân trên bàn cờ là thuộc hạ của chủ hiện tại. Đổi chủ là đổi cả đội, phải xây lại từ thứ có trong tay. Mỗi đời là một ván auto chess mới.
- **Sinh tồn:** sinh tồn của Ấn là giữ chủ sống đủ lâu để đi tới nơi cần đến, hoặc chọn đúng lúc để chủ chết.
- **Kết thúc:** Ấn có thể tìm cách tự hủy, tự hợp lại, hoặc tìm một chủ xứng đáng rồi thôi điều khiển.

### 8.2 "Đò Âm": auto chess ở thế giới người chết

Người chơi là **người lái đò** trên sông Vong Xuyên sau Đêm Nguyệt Liệt. Hồn người chết
nợ nghiệp không qua sông được. Mỗi hồn phải **đấu một ván cờ với chính ký ức của mình**:
quân trên bàn cờ là những người họ từng thương, từng hại, từng bỏ rơi.

- Mỗi trận là một cuốn truyện ngắn: thắng thì hồn nhớ lại một sự thật, thua thì hồn quên thêm một người.
- Người lái đò quyết định hồn nào được qua, hồn nào bị giữ lại làm quân cờ cho mình. Giữ càng nhiều càng mạnh, nhưng chính mình cũng đang nợ nghiệp.
- **Sinh tồn:** dầu đèn lồng trên đò. Hết dầu thì đò lạc vào sương, và người lái đò trở thành hồn cần được chở.
- **Cú ngoặt:** về sau người chơi nhận ra hồn trên đò là những người đã chết trong các ván chơi trước của chính mình (hoặc của người chơi khác, xem 8.5).

### 8.3 "Gia Phả": một dòng họ qua trăm năm

Người chơi điều khiển **một dòng họ** qua 5–7 thế hệ. Mỗi thế hệ là một chương auto chess
và sinh tồn kéo dài một đời người, rồi thời gian nhảy 20–30 năm.

- Nhân vật sinh ra, lớn lên, kết hôn khác tộc, có con mang dòng máu lai. Con cái thừa hưởng tài năng, sẹo, mối thù và lời thề của cha mẹ. Dàn nhân vật tự sinh ra vô hạn, mỗi người đều có gốc gác.
- **Nhân quả xuyên đời:** ông nội bỏ rơi một đứa con rơi, ba mươi năm sau cháu của đứa trẻ đó dẫn quân về đòi đất.
- **Phản bội trong nhà:** anh em tranh quyền thừa kế. Người chơi chọn ai làm tộc trưởng và phải sống với những đứa con không được chọn.
- Bàn cờ auto chess là cả họ: già dặn mà yếu sức, trẻ khỏe mà non.

### 8.4 "Hai Mặt Trận": đánh cả hai phe của một cuộc chiến

Mỗi chương người chơi đổi phe. Chương lẻ là phe triều đình, chương chẵn là phe Lang Tộc
nổi dậy, cùng một cuộc chiến, cùng mốc thời gian.

- Đội hình chương trước trở thành **đội địch** ở chương sau, do AI điều khiển đúng như cách người chơi đã xếp. Người chơi phải đánh bại chính chiến thuật của mình.
- Ai mình cứu ở phe này, mình phải giết ở phe kia. Kết thúc thật chỉ mở khi người chơi tìm cách để cả hai phe cùng sống.
- Đây là cách đưa "không có phe ác" từ lời nói thành luật chơi.

### 8.5 "Thế Giới Chung Nghiệp": nhân quả nối giữa những người chơi

Một lớp mạng nhẹ ghép được vào bất kỳ hướng nào ở trên.

- Nhân vật người chơi khác bỏ rơi hoặc phản bội sẽ trôi sang thế giới của mình thành **lữ khách**, **Vong Nhân** hoặc **kẻ báo thù**, mang theo tên và câu chuyện từ ván của người kia.
- Mỗi mùa, máy chủ cộng dồn lựa chọn của mọi người chơi để quyết định vận mệnh của một châu: nếu đa số phản bội Lang Tộc, mùa sau Lang Tộc thù ghét tất cả.
- Kỹ thuật vẫn nhẹ: chỉ gửi bản ghi nhỏ (id nhân vật, loại Nhân, đội hình, seed), không cần máy chủ thời gian thực. Chơi offline vẫn được, chỉ thiếu lữ khách từ thế giới khác.

### 8.6 Đề xuất mới: "Ấn Truyền" làm xương sống, ghép thêm 8.2 và 8.5

| Lớp | Lấy từ | Vai trò |
|---|---|---|
| Người chơi là Ấn, nhảy từ chủ này sang chủ khác | 8.1 | Lõi kể chuyện và lõi phản bội |
| Chủ cũ chết thì xuống Đò Âm, có thể quay lại làm quân hoặc làm địch | 8.2 | Mất mát có hậu quả, thêm một tầng thế giới |
| Chủ bị bỏ rơi và nghiệp trôi sang thế giới người chơi khác | 8.5 | Chơi mạng gắn với chủ đề, không phải tính năng gắn thêm |
| Hạ trại sinh tồn và Sổ Nhân Quả | Mục 4 | Giữ nguyên, Sổ đổi tên thành "vết ấn" |

**Vì sao chọn:** đây là hướng duy nhất mà cả năm thứ Phúc muốn (phản bội, mất mát, nhân
quả, nhân văn, dàn nhân vật vô hạn) đều là luật chơi chứ không chỉ là nội dung. Câu hỏi
nhân văn nằm sẵn trong cơ chế: một thứ sức mạnh sống bằng cách đổi người, nó có nên tồn tại?

**Rủi ro và cách giảm:**

- *Người chơi không gắn bó với ai vì chủ đổi liên tục.* Giữ mỗi đời chủ đủ dài (một chặng 20–40 phút), và cho một nhóm nhỏ nhân vật "theo Ấn" xuyên các đời (kẻ săn Ấn, người hầu trung thành, đứa con của chủ đầu tiên).
- *Đổi đội liên tục làm auto chess rối.* Cho Ấn giữ lại 1–2 "mảnh ký ức" (kỹ năng hoặc quân) từ mỗi đời chủ.
- *Nội dung nhiều.* Mỗi chủ là một CharacterDef cộng một bộ sự kiện nhỏ; vẫn theo khuôn dữ liệu ở mục 4.6.

**Bản thử đầu tiên cho hướng này:** 3 đời chủ (một tướng Nhân tộc, cận vệ Lang Tộc phản
chủ, một đứa trẻ Lân Thủy nhặt được Ấn), 1 lần xuống Đò Âm, 1 Vong Nhân quay lại làm địch.
Đủ để thử cảm giác "nhảy chủ" có cuốn không.

## 9. Câu hỏi còn mở cho Phúc

1. Hướng nào làm anh hứng nhất: "Ấn Truyền", một hướng khác ở mục 8, hay muốn quay về phương án A?
2. Giọng điệu u tối đến mức nào: kiểu bi tráng có hy vọng, hay tàn khốc thật sự?
3. Phong cách hình ảnh cho sprite trận: pixel art, vẽ tay phẳng, hay kiểu cắt giấy có khớp?
4. Tử trận vĩnh viễn là mặc định, hay để người chơi chọn ngay từ đầu?
