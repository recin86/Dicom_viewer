# DICOM Viewer 시스템 아키텍처

이 문서는 Rust 영상 코어와 Swift macOS 앱의 책임 및 실행 흐름을 정의한다. 목표는 DICOM의 의미와 수치 처리를 화면에서 독립적으로 검증하고, macOS의 입력과 GPU 표시 기능을 직접 활용하는 구조다.

문서 버전 0.2 · 작성·검토일 2026-09-30 · 상태 검토·보완한 설계 초안. Rust/dicom-rs와 Swift의 사용은 확정 사항이다. UniFFI 연결과 픽셀 전달 방식은 P0 종료에서 채택했다(ADR 0002). SwiftUI/AppKit/Metal, SQLite와 아래 모듈 분할은 설계 제안이다.

## 구성과 책임

```text
사용자 파일과 폴더
       │  Swift의 파일 선택 및 접근 권한 관리
       ▼
Rust core ── DICOM 읽기와 디코딩
   │         프레임 해석과 공간 정보
   │         캐시, 측정, 인덱스와 프로젝트 저장
   │
UniFFI ──── 요약 정보, 명령, 오류, 프레임 handle (픽셀은 타입 있는 C 복사 함수로 Swift 버퍼에 1회 복사)
   │
Swift app ─ 탐색 상태, 도구 상태, cine 스케줄링
   ├─────── SwiftUI 앱 화면
   └─────── AppKit 영상 입력 → Metal 영상 표시
```

앱 프로세스 안에 코어 라이브러리를 포함한다. 로컬 서버나 고정 네트워크 포트는 필요하지 않다. 스레드와 작업 큐로 백그라운드 처리를 분리하며, 별도 프로세스 디코더는 향후 장애 격리 필요성이 확인될 때 검토한다.

| 구성 | 소유하는 책임 | 경계 |
| --- | --- | --- |
| Rust domain | Study/Series/Instance/Frame, 공간과 시간 모델, 단위, 측정 계산 | Swift나 Metal 타입에 의존하지 않음 |
| Rust DICOM adapter | dicom-rs 호출, SOP/코덱 판정, 태그 정규화, 픽셀 해석 | 외부 라이브러리 객체를 FFI로 직접 노출하지 않음 |
| Rust engine | 인덱싱, 프레임 요청, 작업 우선순위, CPU 캐시, 취소 | UI 상태를 직접 변경하지 않음 |
| Rust persistence | SQLite 인덱스, 프로젝트 직렬화, 마이그레이션, 내보내기 데이터 | macOS 파일 권한 획득은 Swift가 담당 |
| FFI facade | 명시적 API, 오류 변환, 데이터 소유권 | Rust 내부 구조 변경의 영향을 제한 |
| Swift app model | 활성 뷰, 선택, 도구, 재생과 작업 상태 | DICOM 태그의 의미를 다시 해석하지 않음 |
| Swift renderer | Metal 리소스, shader, 화면과 픽셀 좌표 변환 | 정규화된 표시 설명을 사용 |
| Swift platform | 파일 선택, 접근 권한, 창, 메뉴, 단축키 | OS별 처리를 코어에 전파하지 않음 |

SwiftUI에 AppKit 뷰를 넣는 경계에는 NSViewRepresentable을 사용하고, 영상 표시는 MTKView를 검토한다. 이는 Apple의 뷰 통합 API에 기반한 제안이다. [NSViewRepresentable](https://developer.apple.com/documentation/swiftui/nsviewrepresentable), [MTKView](https://developer.apple.com/documentation/metalkit/mtkview/)

## 코어 경계와 빌드

코어는 정적 라이브러리로 빌드해 앱에 연결하고 UniFFI 0.32.2로 Swift 바인딩을 생성한다(P0 종료 채택). 대상 Mac에서 Xcode 없이 Command Line Tools와 SwiftPM으로 빌드·정적 링크를 확인했다. 앱 번들 패키징과 서명은 P5에서 검증한다. 생성기와 런타임 버전은 함께 고정한다. [UniFFI Xcode 연동](https://mozilla.github.io/uniffi-rs/latest/swift/xcode.html)

초기에는 Rust 모듈로 책임을 나누고, 실제 재사용이나 빌드 시간의 이점이 있을 때 crate를 분리한다. 범용성을 이유로 첫 단계부터 과도한 인터페이스 계층이나 플러그인 시스템을 만들지 않는다.

예상 코드 배치는 다음과 같다. 아래 폴더는 아직 생성하지 않았다.

```text
crates/viewer-core/    domain, dicom, engine, measurement, persistence
crates/viewer-ffi/     UniFFI 공개 API
macos/                Swift 앱, AppKit viewport, Metal shaders
tests/                작은 합성 fixture와 통합 시험
scripts/              빌드와 검증 자동화
docs/                 현재 개발 문서
```

## 폴더를 여는 흐름

1. Swift가 파일 선택 결과를 받고 필요한 접근 권한의 수명을 유지한다.
2. Rust가 확장자에만 의존하지 않고 후보 파일을 검사한다. 재귀 탐색은 방문 경로를 추적하고 기본적으로 심볼릭 링크를 따라가지 않는다.
3. 메타데이터를 우선 읽어 검사와 시리즈 요약을 점진적으로 제공한다. 픽셀 전체 디코딩은 선택된 프레임이나 썸네일 생성 시 수행한다.
4. 동일 SOP Instance UID의 다른 내용, 누락 UID, 손상 파일을 별도 결과로 남긴다.
5. 선택된 시리즈에서 공간 스택, 시간 시퀀스 또는 순서만 있는 프레임 목록을 구성한다.
6. 현재 프레임을 우선 디코딩하고, 여유 자원이 있을 때 주변 프레임과 썸네일을 읽는다.

메타데이터만 읽는 경로와 프레임 단위 디코딩이 모든 코덱에서 동일한 비용을 갖는다고 가정하지 않는다. 전체 객체 로딩이 필요한 입력은 비용과 제한을 기록하고 P0/P2에서 측정한다.

## 픽셀과 표시의 경계

회색조는 Rust가 signedness와 유효 비트, padding을 해석하고 Modality 변환을 한 번 적용한 F32 버퍼를 전달하는 것을 초기 계약으로 제안한다. Swift는 이를 단일 채널 텍스처로 올린다. VOI와 최종 표시 극성은 Rust가 구성한 DisplayDescriptor를 사용해 Metal에서 적용한다.

dicom-pixeldata의 변환 API는 Modality/VOI 처리를 포함할 수 있다. adapter는 선택한 함수와 옵션의 출력 단계를 확인하고, 저장 값·Modality 적용 값·표시 값의 경계를 고정한다. 기본 변환 옵션에 의존해 rescale 또는 VOI를 두 번 적용하지 않는다. P0에서 음수 intercept와 비단위 slope를 가진 자료로 이 경계를 확인한다. [dicom-pixeldata 0.10.0](https://docs.rs/dicom-pixeldata/0.10.0/dicom_pixeldata/)

이 선택은 UI의 반복 태그 해석을 줄이는 대신, 원본 16비트보다 전달 버퍼가 커진다. 실제 비용을 측정한 후 필요하면 원본 정수 버퍼 경로를 추가한다. 계산용 원본 값과 변환 정보는 Rust에 남겨 ROI와 픽셀 조회에 사용한다. F32 표시 버퍼를 원본 정밀도의 대체물로 사용하지 않는다.

컬러는 지원되는 RGB/YBR/Palette 표현을 Rust에서 해석해 RGBA8 표시 버퍼로 정규화하는 작업안이다. 지원하지 않는 색상·LUT 조합은 명시적으로 실패시킨다. 컬러 프레임에 회색조 window/level 처리를 적용하지 않는다.

Metal 구현과 비교할 작은 CPU 기준 렌더러를 Rust에 둔다. 이는 시험용 기준 경로이며 정상 사용에서 매 드래그마다 CPU 이미지를 재생성하지 않는다. 두 구현은 동일한 표시 설명과 시험 벡터를 사용한다.

window/level, pan, zoom 변경은 이미 올라간 텍스처를 재사용한다. 화면 표시, 방향 문자, 주석은 같은 기하 변환을 사용해야 한다. 픽셀 선택은 화면 변환의 역변환으로 원본 픽셀 좌표를 얻는다.

Rust는 표시용 픽셀 종횡비와 그 근거를 함께 제공한다. Swift는 이를 반영해 fit과 회전·뒤집기를 계산한다. 화면 비율을 위한 정보만으로 mm 측정을 활성화하지 않는다. 실제 변환 순서와 픽셀 경계는 [API 계약](04-core-api-and-data-model.md)에서 관리한다.

## 스레드와 요청 수명

Swift UI 변경은 MainActor에서 수행한다. 파일 읽기와 디코딩을 MainActor의 동기 호출로 실행하지 않는다. Swift가 만든 Task가 자동으로 무거운 동기 FFI 호출을 백그라운드로 옮긴다고 가정하지 않는다.

Rust engine은 제한된 작업 큐와 디코딩 worker를 소유한다. 동시성 숫자는 P0에서 정하고 설정으로 제한할 수 있게 한다. 코덱 자체의 내부 스레드와 worker 수를 함께 고려해 과도한 병렬 실행을 피한다.

모든 뷰 요청에는 viewport ID와 단조 증가하는 generation을 붙인다. 사용자가 다른 프레임을 선택하면 이전 요청을 취소하고 generation을 올린다. 결과는 frame ID와 generation이 현재 선택과 일치할 때만 화면에 반영한다. 코덱 내부에서 즉시 취소할 수 없더라도 오래된 결과를 표시하지 않는 계약은 지킨다.

source revision, display set의 grouping revision 또는 세션이 바뀔 때도 generation을 갱신한다. 가져오기 중 set에 프레임이 추가되어도 현재 표시 프레임은 FrameRef로 유지하고 목록의 같은 인덱스로 바꾸지 않는다. 측정 결과는 frame reference와 도형 revision까지 일치해야 반영한다.

화면에 실제로 표시된 프레임과 사용자가 요청한 프레임을 별도로 관리한다. 다음 프레임이 로딩 중일 때 이전 영상 위에 새 프레임의 번호나 측정을 표시하지 않는다.

## 캐시와 메모리

| 계층 | 주 소유자 | 키와 해제 기준 |
| --- | --- | --- |
| 파일 메타데이터 | Rust | Source ID와 파일 revision, 파일 변경 시 무효화 |
| 디코딩 픽셀 | Rust | Frame ID, source revision, decoder revision, 출력 단계 |
| 표시 버퍼 | Rust 보유 불변 프레임, Swift 복사본 | 디코딩 키와 표시 버퍼 형식, Swift 소유 버퍼로 1회 복사 |
| GPU 텍스처 | Swift renderer | Frame ID와 payload revision, GPU 사용 종료 후 재활용 |
| 썸네일 | Rust 및 디스크 캐시 | 원본 revision과 thumbnail recipe version |

FFI는 Rust 보유 프레임을 Swift 소유 버퍼로 한 번 복사해 전달한다([ADR 0002](adr/0002-uniffi-and-pixel-buffers.md), P0 종료 채택). Rust 포인터를 Swift에 빌려주지 않는다. FFI 복사와 GPU 업로드의 비용, Rust 보유본과 Swift 버퍼가 함께 존재하는 메모리(복사 중과 Swift가 handle을 보유하는 동안)를 자원 예산에 포함하며 zero-copy라고 표현하지 않는다. 포인터 공유는 성능 병목이 확인된 뒤 별도 ADR로 도입한다.

캐시는 프레임 개수보다 바이트 기준으로 제한한다. 현재 화면 리소스, 재생 준비 프레임, 일반 미리 읽기의 순서로 우선순위를 둔다. CPU/GPU 리소스와 전송 중 버퍼를 함께 계측한다. Metal 리소스 해제는 해당 command buffer의 사용 완료 이후에만 한다.

메모리 압박 시 미리 읽기를 줄이고 낮은 우선순위 캐시를 해제한다. 단일 프레임 자체가 한도를 넘으면 ResourceLimit 오류를 제공한다. 해상도를 몰래 낮춘 프레임을 원본이라고 표시하지 않는다.

EngineConfig의 제한은 캐시뿐 아니라 입력 바이트, 메타데이터 중첩·요소 수, 압축 해제 출력, 전체 객체 디코딩, 대기 작업과 진행 중 버퍼에도 적용한다. 크기 곱셈은 할당 전에 검사한다. 현재 화면에 고정된 리소스 때문에 새 요청을 수용할 수 없으면 미리 읽기를 중단하고 새 할당을 거부한다. 코덱 내부 메모리까지 제한할 수 없는 경로는 그 한계를 기록하고 P0에서 보수적인 입력 제한을 정한다.

## 인덱스와 연구 프로젝트

SQLite 인덱스에는 파일 위치, 관찰한 revision, UID, 최소 요약과 지원 상태를 저장한다. 원본으로부터 재생성할 수 있는 자료이다. 환자 메모와 주석의 유일한 저장소로 사용하지 않는다.

연구 프로젝트는 버전이 있는 독립 문서로 저장한다. 프레임 참조, 측정, 메모, 레이아웃과 표시 상태를 포함하며 원본 영상은 참조한다. 구체적인 형식은 [API와 데이터 모델](04-core-api-and-data-model.md)의 영속 데이터 계약을 따른다.

실행 중 ViewState의 session/display set ID를 프로젝트에 그대로 저장하지 않는다. 저장용 상태는 영속 프레임 참조와 그룹 선택 조건을 사용한다. 저장은 편집 revision별 snapshot으로 직렬화하고, 쓰는 동안 새 편집이 발생하면 이전 snapshot 저장 완료 후에도 변경됨 상태를 유지한다.

파일 접근에 security-scoped bookmark가 필요한 배포 모드라면 Swift가 생성·해제·갱신을 담당한다. Rust의 백그라운드 파일 접근이 끝나기 전에 권한 수명을 종료하지 않는다. 일반 파일 경로와 플랫폼 bookmark는 다른 필드로 관리한다.

## 오류와 진단

한 파일의 해석 오류는 해당 파일의 실패로 처리한다. 프로젝트 저장 실패는 dirty 상태를 유지하고 원인을 표시한다. 원본 변경을 발견하면 캐시를 무효화하고 저장된 주석의 자동 적용을 중단해 재연결 확인이 가능하게 한다.

예상 오류는 구조화한 오류 값으로 반환한다. Rust panic이 FFI 경계를 넘어 unwind하지 않게 하고, recoverable error를 panic으로 구현하지 않는다. 같은 프로세스의 네이티브 코덱 crash까지 이 설계가 격리해준다고 가정하지 않는다.

일반 로그에는 기능명, 오류 코드, 작업 ID와 시간만 기록한다. 환자 정보나 원문 태그가 필요한 상세 진단은 사용자가 확인 가능한 별도 동작으로 설계한다.

## 관련 설계 결정

- [Rust 코어와 Swift 앱 분리](adr/0001-rust-core-swift-app.md)
- [UniFFI 연결과 픽셀 버퍼](adr/0002-uniffi-and-pixel-buffers.md)
- [Metal 표시와 프레임 모델](adr/0003-metal-and-frame-model.md)
- [로컬 인덱스와 연구 프로젝트](adr/0004-local-storage.md)
