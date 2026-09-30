# UniFFI 연결과 픽셀 버퍼

상태: 제안. 날짜: 2026-09-30. 결정 시점: P0 종료. 관련 문서: [시스템 아키텍처](../02-system-architecture.md), [API와 데이터 모델](../04-core-api-and-data-model.md).

## 배경

검사 요약, 오류와 세션 객체는 Swift에서 다루기 쉬운 API가 필요하다. 영상은 프레임별로 큰 버퍼를 전달하므로 연결 코드의 유지보수와 메모리 복사 비용을 함께 고려해야 한다.

## 선택 제안

UniFFI로 Swift 바인딩을 생성하고 Rust 정적 라이브러리를 앱에 연결한다. metadata와 제어 API는 구조화한 값으로 노출한다. 초기 프레임은 소유된 bytes와 descriptor로 전달하며 zero-copy를 요구하지 않는다.

공개 API는 DICOM 라이브러리 객체 전체를 그대로 노출하지 않는다. request ID, frame reference, 변환 단계와 오류를 명시한다. 디코딩 결과를 JSON이나 PNG로 바꿔 전달하는 중간 경로를 기본으로 사용하지 않는다.

UniFFI의 Xcode 문서는 정적 라이브러리와 생성된 Swift 연결을 설명한다. 실제 macOS 프로젝트 빌드와 비동기 타입 표현은 별도 실험으로 확인한다. [UniFFI Xcode 연동](https://mozilla.github.io/uniffi-rs/latest/swift/xcode.html)

## 검토한 대안

작은 C ABI는 픽셀 포인터와 수명을 세밀하게 다룰 수 있지만 문자열, 오류, 객체와 비동기 작업의 수작업 연결 코드가 늘어난다. Swift와 Rust 사이의 다른 bridge 라이브러리도 후보가 될 수 있으나, 우선 하나의 연결 방식을 검증한다.

전체 API를 C ABI로 만드는 대신, 실제 병목이 확인된 픽셀 전달만 별도 경로로 추가하는 대안도 있다. 두 경로가 같은 buffer lifetime과 frame revision을 사용하도록 설계해야 한다.

## 결과

생성기와 런타임 버전을 함께 고정하고 생성된 Swift 코드도 빌드에서 검증해야 한다. 큰 프레임의 복사가 CPU/GPU 메모리 사용을 늘릴 수 있다. 수명을 단순하게 유지하는 초기 비용으로 이를 수용하고 계측한다.

borrowed bytes 기능을 검토할 때는 채택한 버전의 지원 방향과 수명 제한을 확인해야 한다. 현재 선택은 Rust 반환 픽셀의 무복사에 의존하지 않는다. byte buffer 안내의 세부 기능은 P0에서 생성된 Swift 코드와 함께 재확인한다. [UniFFI byte buffers](https://mozilla.github.io/uniffi-rs/latest/types/bytes.html)

## 검증과 재검토

P0에서 대표 크기의 회색조 및 컬러 버퍼 전달 시간, 할당 수, peak memory, 취소와 close 수명을 측정한다. 바인딩 코드에서 bytes가 어떤 Swift 타입으로 변환되는지도 확인한다.

FFI 복사가 전체 목표를 막는 병목이라는 근거가 있거나 공개 API를 충분히 표현하지 못하면 대안을 검토한다. 포인터 공유를 도입할 때는 retain/release, thread 규칙, allocator, cache eviction과 GPU 작업 완료를 새로운 계약으로 기록한다.
