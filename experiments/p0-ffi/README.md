# P0-FFI 실험

UniFFI 0.32.2로 Rust 정적 라이브러리를 만들고, Xcode 없이 SwiftPM(Command Line Tools)으로 Swift에서 호출해 다음을 확인한다. 일회성 실험이며 제품 API가 아니다. 계획: [P0-tech-data.md](../../docs/implementation/P0-tech-data.md)

실행: `bash experiments/p0-ffi/run.sh` → `results/p0-ffi-report.txt`, 빌드 로그 `results/p0-ffi-build.log`

| 구분 | 확인 내용 | 관련 |
| --- | --- | --- |
| 1 | 구조화 오류(InvalidArgument/ResourceLimit/Cancelled), Rust panic이 Swift 오류로 전달되고 앱이 죽지 않는지 | docs/04 오류 모델, docs/02 panic 경계 |
| 2 | Rust→Swift 소유 버퍼(1/16/64 MiB) 시간 p50/p95, FFI 비용 분리, 길이·stride·checksum·샘플 픽셀 검증 | ADR 0002, T-11 |
| 3 | Swift→Rust 64 MiB: `Vec<u8>`(복사) vs `&[u8]`(0.32 무복사) | ADR 0002 |
| 4 | Rust 캐시 비우기·객체 해제 후 반환 payload 유효성 | docs/04 메모리 소유권 |
| 5 | 16 MiB × 200회 반복 시 메모리 증가 | T-11, QR-03 |
| 6 | async Rust 함수 / MainActor에서 동기 호출 / Task.detached 동기 호출 시 MainActor 응답성 | docs/02 스레드 규칙, QR-02 |
| 7 | 명시적 취소 토큰 vs Swift Task.cancel() | docs/04 요청과 취소, T-12 |

빌드 산출물은 OneDrive 밖 `~/Library/Caches/dicom-viewer/p0-ffi/`에 둔다 (`CARGO_TARGET_DIR`가 설정돼 있으면 그 경로).

생성된 바인딩에서 확인한 사항 (Linux에서 사전 생성, 2026-09-30): 레코드 안의 `Vec<u8>`는 Swift `Data`가 되며 `RustBuffer` 직렬화 후 `Data(readBytes(...))`로 읽으므로 최소 1회 이상 복사된다. 길이는 Int32로 인코딩되어 한 값이 2 GiB를 넘을 수 없다.
