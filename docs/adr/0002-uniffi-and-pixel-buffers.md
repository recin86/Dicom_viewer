# UniFFI 연결과 픽셀 버퍼

상태: **채택** (P0 종료, 2026-09-30; 최초 제안 같은 날). 관련 문서: [시스템 아키텍처](../02-system-architecture.md), [API와 데이터 모델](../04-core-api-and-data-model.md). 근거: [P0-FFI](../../experiments/p0-ffi/README.md), [P0-FFI-CONTRACT](../../experiments/p0-ffi-contract/README.md).

## 배경

검사 요약, 오류와 세션 객체는 Swift에서 다루기 쉬운 API가 필요하다. 영상은 프레임별로 큰 버퍼를 전달하므로 연결 코드의 유지보수와 메모리 복사 비용을 함께 고려해야 한다.

## 선택 제안

UniFFI로 Swift 바인딩을 생성하고 Rust 정적 라이브러리를 앱에 연결한다. metadata와 제어 API는 구조화한 값으로 노출한다. 프레임 픽셀은 zero-copy를 요구하지 않는다.

최초 제안은 레코드 안의 소유된 bytes 반환이었다. P0-FFI 실측에서 이 경로는 16 MiB 이상 프레임을 반복 수신할 때 호출당 약 한 프레임씩 footprint가 쌓였고(원인은 Rust 누수가 아닌 반환 경로의 해제 시점으로 추정, 미확정), Rust 보유 프레임에서 Swift 소유 버퍼로 한 번 복사하는 경로는 footprint가 평탄했다. 따라서 채택안은 다음과 같다.

- Rust는 디코딩된 불변 프레임을 보유한다. UniFFI 객체가 형식·크기·stride·value domain·mask 길이·revision과 불투명 copy ticket을 제공한다.
- 픽셀과 valid mask는 타입 있는 작은 C 함수(`ticket`, `uint8_t *dst`, `size_t dst_len`)로 Swift 소유 버퍼에 정확히 한 번 복사한다. ticket은 주소가 아니며 재사용하지 않는다. 정확한 길이만 허용하고, ticket·null·mask·길이 오류는 대상에 쓰지 않는다. 모든 진입점은 panic을 상태 코드로 격리한다.
- Swift 코드는 C 함수를 직접 부르지 않는다. 안전 래퍼가 객체 수명을 호출 동안 연장하고, 정확한 크기의 Swift 버퍼를 할당하거나 배타적(`inout`) 버퍼 또는 shared `MTLBuffer`를 길이 검사 후 채운다. Rust 포인터는 Swift로 나가지 않고 Swift 목적지 포인터도 Rust가 보관하지 않는다.
- 이미 받은 프레임 handle과 복사된 Swift 버퍼는 캐시 eviction·세션 close와 독립적으로 유효하다. 마지막 owner가 사라지면 ticket은 만료된다.
- 기존 실험의 `copy_into(dst_addr: u64)`처럼 임의 정수 주소를 받는 공개 메서드는 쓰지 않는다. UniFFI가 안전한 `&mut [u8]` 인자를 정식 제공하면 같은 의미로 교체를 검토한다.

공개 API는 DICOM 라이브러리 객체 전체를 그대로 노출하지 않는다. request ID, frame reference, 변환 단계와 오류를 명시한다. 디코딩 결과를 JSON이나 PNG로 바꿔 전달하는 중간 경로를 기본으로 사용하지 않는다.

UniFFI의 Xcode 문서는 정적 라이브러리와 생성된 Swift 연결을 설명한다. 실제 macOS 프로젝트 빌드와 비동기 타입 표현은 별도 실험으로 확인한다. [UniFFI Xcode 연동](https://mozilla.github.io/uniffi-rs/latest/swift/xcode.html)

## 검토한 대안

작은 C ABI는 픽셀 포인터와 수명을 세밀하게 다룰 수 있지만 문자열, 오류, 객체와 비동기 작업의 수작업 연결 코드가 늘어난다. Swift와 Rust 사이의 다른 bridge 라이브러리도 후보가 될 수 있으나, 우선 하나의 연결 방식을 검증한다.

전체 API를 C ABI로 만드는 대신, 실제 병목이 확인된 픽셀 전달만 별도 경로로 추가하는 대안도 있다. 두 경로가 같은 buffer lifetime과 frame revision을 사용하도록 설계해야 한다.

## 결과

생성기와 런타임 버전(UniFFI 0.32.2)을 함께 고정하고 생성된 Swift 코드도 빌드에서 검증해야 한다. 생성 바인딩은 손으로 고치지 않는다. 손으로 쓴 C 경계가 하나 생기므로 헤더·Rust producer·Swift 래퍼·계약 시험을 같은 변경 묶음으로 유지한다. 큰 프레임은 Rust 보유본과 Swift 버퍼로 두 벌이 존재하며, GPU 업로드까지 복사가 추가될 수 있다. shared `MTLBuffer`를 직접 목적지로 쓰면 CPU 복사를 한 번으로 줄일 수 있으나 GPU 사용 완료와의 순서는 P1에서 계약·시험한다.

borrowed bytes 기능을 검토할 때는 채택한 버전의 지원 방향과 수명 제한을 확인해야 한다. 현재 선택은 Rust 반환 픽셀의 무복사에 의존하지 않는다. byte buffer 안내의 세부 기능은 P0에서 생성된 Swift 코드와 함께 재확인한다. [UniFFI byte buffers](https://mozilla.github.io/uniffi-rs/latest/types/bytes.html)

## 검증과 재검토

P0에서 대표 크기의 회색조 및 컬러 버퍼 전달 시간, 할당 수, peak memory, 취소와 close 수명을 측정한다. 바인딩 코드에서 bytes가 어떤 Swift 타입으로 변환되는지도 확인한다.

FFI 복사가 전체 목표를 막는 병목이라는 근거가 있거나 공개 API를 충분히 표현하지 못하면 대안을 검토한다. 포인터 공유를 도입할 때는 retain/release, thread 규칙, allocator, cache eviction과 GPU 작업 완료를 새로운 계약으로 기록한다.

## P0 증거 (대상 Mac: Apple M5, macOS 27.0, Rust 1.98.1, Swift 6.4 CLT, 정적 링크)

- P0-FFI: Xcode 없이 UniFFI 빌드·정적 링크, 구조화 오류·Result 경로 panic·async·명시적 취소 토큰 확인. 레코드 bytes 경로 64 MiB 전달 p50 34 ms와 footprint 누적, into 경로 64 MiB p50 1.86 ms와 평탄한 footprint.
- P0-FFI-CONTRACT: 합성 GrayF32LE(mask 포함)·RGBA8 전 픽셀 bit 일치, 오류 상태·미기록, eviction·close 후 payload 유효·ticket 만료, 동시 복사와 해제 경합 200회에서 부분·부활 없음, C 경계 panic 격리, 복사 중 Rust 할당 0, 64 MiB 반복 복사 footprint 평탄, 64 MiB 복사 p50 약 1.1 ms, shared `MTLBuffer` 목적지 일치.
- 범위 밖: 실제 `decode_frame`·요청 generation·취소 경합·GPU 표시·T-11~T-13 정식 합격은 P1 이후 제품 시험이다. Swift 래퍼는 임의 비null 포인터의 유효성을 C 경계에서 검증할 수 없다는 한계를 래퍼 전용 사용으로 관리한다.
