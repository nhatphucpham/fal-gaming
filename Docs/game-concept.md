# Falemag: ý tưởng cốt lõi (bản phác 3)

> Trạng thái: bản nháp để bàn. Bản 3 (mục 8) là ba thế giới mới có chiều sâu; đề xuất
> "Kỳ Hội". Hướng "Ấn Truyền" của bản 2 đã bị Phúc loại. Các mục 3–7 là bản 1, giữ để so sánh.
> Bản trực quan: artifact "Ba Thế Giới Falemag". Mọi tên riêng (thế giới, tộc, nhân vật) là tên tạm,
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

## 8. Ba thế giới mới (bản 3)

Phúc thấy bản 1 an toàn, bản 2 ("Ấn Truyền") thiếu chiều sâu và không hợp. Bản 3 đưa ba
thế giới, mỗi cái có: một sự thật ẩn dưới thế giới, một cơ chế lõi riêng, các hệ thống móc
vào nhau, và thêm yếu tố ngoài sở thích ban đầu (kinh tế, chính trị, sinh thái, thế hệ,
giải đấu, tín ngưỡng, dư luận).

### 8.1 Kỳ Hội (đề xuất)

- **Thế giới:** sau Chiến tranh Bách Tộc, chín tộc ký Kỳ Ước: cấm quân quá 30 người, mọi
  tranh chấp phân xử bằng Kỳ Chiến (tối đa 9 đấu sĩ trên Kỳ Đài, Kỳ Viện Thạch Duệ giám sát,
  kết quả trói bằng huyết thệ). Auto chess là luật của thế giới.
- **Sự thật ẩn:** huyết thệ sống bằng máu đổ trên Kỳ Đài. Trường phái "đánh không giết" làm
  Ước yếu dần, nên Kỳ Viện bí mật dàn xếp trận đẫm máu. Phe Thiết Huyết muốn xé Ước, quay lại
  chiến tranh thật.
- **Người chơi:** thừa kế Kỳ Quán Thanh Đăng đang lụi tàn ở thành cảng Lâm Giang; thầy vừa
  chết trong một trận bị dàn xếp.
- **Nhịp:** trận (hợp đồng, do thám, xếp quân, lời thề trước trận, cho phép xin hàng) ->
  mùa (chiêu mộ, tập, chữa, lương, sống còn trong thành, chọn hợp đồng) -> chiến dịch
  (bảng Kỳ Hội chín châu, kẻ giết thầy, bí mật Kỳ Viện, số phận Kỳ Ước).
- **Hệ thống:** hợp đồng là lựa chọn đạo đức; nhân quả trở về thành người (tị nạn, kẻ thù,
  ân nhân); đấu sĩ là con người (gia đình, thương tật vĩnh viễn, con cái vào lò); dàn xếp và
  phản bội; Kỳ Đài theo vùng, lời thề, khán giả; kinh tế, Danh, Ân, quyền của các tộc.
- **Chơi mạng:** các lò của người chơi đấu nhau trong cùng giải (bất đồng bộ, tất định).
- **Kết thúc:** giữ Ước và cải tổ / xé Ước / lập Ước mới không bằng máu / vào Kỳ Viện.

### 8.2 Long Mạch

- **Thế giới:** đại lục là thân thể Ngao Mẫu đang ngủ; long mạch là sinh khí rỉ ra; mỗi tộc
  sinh từ một phần của bà, riêng người Nhân từ biển đến và dựng chế độ khai thác mạch.
- **Sự thật ẩn:** bà mơ lại những gì người ta làm; hút quá tay gây Cơn Co, ác mộng thành Mộng
  Thú (nhân quả là sinh thái). Bà đang mang thai một thế giới mới.
- **Người chơi:** chúa thái ấp Vĩ Châu (vùng đuôi), dòng lai Nhân và Mộc Hồn, qua nhiều đời.
- **Hệ thống:** hút hay chữa mạch; bách khoa Mộng Thú; chư hầu và hôn nhân; quan điểm các tộc
  về người Mẹ; thế hệ; hành hương.
- **Chơi mạng:** mọi người chơi trong một mùa máy chủ sống chung một Ngao Mẫu (bi kịch của chung).
- **Kết thúc:** hút cạn / di cư sang đứa con / đánh thức / tự hiến thành mạch mới.

### 8.3 Thịnh Suy

- **Cấu trúc:** một vương triều qua 300 năm, bốn thời đại: Khai (sinh tồn), Thịnh (chiến lược),
  Suy (âm mưu), Diệt (người chơi thành phe nổi dậy chống chính vương triều mình dựng).
- **Sự thật ẩn:** mọi điều tốt dựng ở thời Khai sẽ thành công cụ áp bức ở thời Suy.
- **Hệ thống:** thẻ luật sống dai và biến dạng; huyền thoại bị kể sai; huyết thống; ca dao.
- **Chơi mạng:** vương triều người khác thành láng giềng hoặc kẻ xâm lăng.

### 8.4 Đề xuất

Kỳ Hội: gọn nhất mà vẫn sâu, mọi lối chơi mọc ra từ một luật của thế giới, vừa sức game 2D
nhẹ. Có thể mượn Mộng Thú (8.2) làm nạn quái vùng biên và cú nhảy thời gian (8.3) làm hậu truyện.

## 9. Câu hỏi còn mở cho Phúc

1. Thế giới nào muốn đào sâu tiếp: Kỳ Hội, Long Mạch hay Thịnh Suy?
2. Điều gì trong ba cái thấy chán hoặc không hợp?
