# Falemag: Bát Trận

> Tài liệu thiết kế đầy đủ (nguồn chuẩn, có số liệu khởi điểm): `Docs/concept-page/bat-tran-gdd.html`,
> artifact "Bát Trận GDD". File này chỉ tóm tắt; nếu hai nơi lệch nhau thì theo GDD.

**Một câu:** auto chess kiếm, cung, giáp, phép, nơi hình dạng đội hình là vũ khí. Người chơi chỉ
chuẩn bị; trận tự đánh, các tầng kết hợp tự kích hoạt nhau thành chuỗi combo.

## Cốt lõi

- **Một ván:** 12 chặng, chặng nào cũng là trận, chúa tể ở chặng 12, 25–35 phút.
- **Một chặng:** chuẩn bị cố định 60 giây, trận 30–45 giây, rồi chọn 1 trong 3 phần thưởng.
- **Bàn 5×3:** số quân trên bàn bằng Cấp người chơi (3 lên 8). Cấp lên bằng lương.
- **Hai đồng tiền:** vàng mua quân; lương lên Cấp (thêm quân, chợ ra quân giá cao).
- **Quân:** 8 lớp, giá 1–5, sao ×1,8. Giá 5 là Tướng Lĩnh; 3 sao thành Thống Lĩnh.
- **Kỹ năng:** Chiêu tự tung khi đầy Khí, Nội tại "khi X thì Y", lắp từ khối ghép.
- **Kết hợp:** nghề, tộc, trận đồ, nguyên tố, trang bị, kỹ năng, Duyên, Tướng Lĩnh; càng nhiều mốc
  càng mạnh (Hợp Lực). Mốc có thể đột biến giữa ván (Kỳ Ngộ).
- **Luật trận:** tất định 20 nhịp/giây trên SimClock, không may rủi trong trận, không hồi máu.
- **Cảnh cắt** hai nhân vật đối mặt ở khoảnh khắc lớn.

## Đã chốt (GDD bản 2.7)

- **Tên:** Bát Trận. Tên trên cửa hàng quốc tế: "Bat Tran: Eight Formations".
- **Phát hành:** trọng tâm là Hành Quân chơi đơn. Bản web chơi thử, rồi PC (Steam), rồi Android và iOS.
  Bóng Quân (đánh bản chụp đội người khác) sau phát hành; Loạn Chiến 8 người khi đủ người chơi.
- **Mô hình:** mua một lần. Điện thoại chơi thử miễn phí đến hết bậc ải 1. Không gacha, không bán sức mạnh.
- **Hình ảnh:** pixel art kiểu game chiến thuật đời GBA (quân chibi trên bàn, cảnh cắt nhìn ngang, chân dung khi thoại), bảng màu ấm lấy từ tranh dân gian.

## Mong muốn của Phúc và giới hạn kỹ thuật

| Mong muốn | Giới hạn |
|---|---|
| Thời phong kiến nhưng kỳ ảo, không hiện thực | Game 2D nhẹ, chạy tốt trên máy yếu và điện thoại |
| Thế giới nhiều chủng tộc | Godot 4.7.x, gameplay viết bằng C++ (GDExtension) |
| Lối chơi chiến thuật, auto chess: kết hợp và tự động | Có thể chơi qua mạng |
| Khó dần, cần nghĩ nhiều nhưng không khó nhìn | Giọng nói sinh từ TTS tts.falevon.com |
| Nhân vật càng nhiều càng tốt | Lối chơi trước, truyện sau |
