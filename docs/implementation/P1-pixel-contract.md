# P1 제품 픽셀 계약

2026-09-30 착수 / 2026-10-01 완료 (Asia/Seoul) · Task `P1-PIXEL-CONTRACT-20260930` · Codex/root · **done (P1 묶음 2, 전체 P1은 진행 중)**.

## 기준과 범위

사용자 요청: 다음 단계 진행. [P1 계획](P1-single-frame.md)의 묶음 2를 수행한다. 기준 HEAD `ca9e8b8`, 브랜치 `codex/p1-foundation`과 이전 P1 골격의 미커밋 변경을 보존한다. 이전 작성 작업은 종료했다. 기준은 docs/02·04, ADR 0002와 docs/06의 T-11/T-13 및 QR-01~03이다.

이번 범위는 불변 픽셀 버퍼, 살아 있는 모든 Rust payload의 예산, 불투명 ticket을 사용하는 C 복사, Swift 소유 버퍼와 제한, 실제 파일에서 준비한 프레임의 양쪽 계약 시험이다. 실제 입력 결합을 확인하기 위해 작은 native 단일 프레임 adapter를 포함하고, 지원하지 않는 변환/압축/차원은 명시적으로 거부한다. UI 파일 열기·VOI·Metal 표시·전체 코덱 지원은 후속 묶음에 남는다.

## 작성권

| Task | 작성자 | 수정 허용 범위 | 상태 |
| --- | --- | --- | --- |
| P1-PIXEL-CORE | dicom_core | crates/viewer-core/src/** 및 Cargo.toml (필요 의존성은 main에 요청) | done·작성권 반환 |
| P1-PIXEL-SWIFT | macos_app | macos/Sources/ViewerBridge/PixelFrames.swift, macos/Sources/ViewerContractChecks/** | done·작성권 반환 |
| P1-PIXEL-FFI | Codex/root | crates/viewer-ffi/**, macos/Package.swift, macos/Sources/ViewerPixelCopy/**, scripts/**, 공통 의존성·문서·결과 | done |
| P1-PIXEL-REVIEW | dicom_reviewer | 읽기 전용 | done·필수 결함 0 |

## PIXEL-1 결정

- Rust budget는 픽셀+mask의 실제 보유 payload 길이를 할당 전에 예약한다. cache·Swift handle·진행 중 C 복사가 같은 Arc를 공유하며 마지막 owner 해제까지 한 번 계수한다. cache eviction/close는 보유 handle의 charge를 없애지 않는다. 실패·drop 경로에서 예약을 반환한다.
- 구현 기본값: payload live 512 MiB, 한 프레임 128 MiB(픽셀+mask). 명시적 작은 한도로 경계 시험했다. 이는 전체 프로세스 RSS 한도가 아니며 parser·입력·allocator·GPU는 별도다. 이번 제한된 adapter는 입력 크기와 준비 동시성을 별도로 제한한다.
- GrayF32LE는 ModalityApplied, RGBA8은 DisplayColor. masked 회색조는 +0.0, mask는 0/1. F64→F32 유한 범위 초과를 정상 값으로 바꾸지 않는다. F32는 향후 F64 측정 경로를 대체하지 않는다.
- C copy는 ticket/null/mask/정확 길이를 검사하고 오류 때 목적지를 쓰지 않는다. ticket은 재사용하지 않으며 registry는 weak, 복사 중에는 strong owner를 확보한다. C panic은 unwind하지 않고 상태로 반환한다.
- C copy 모듈과 생성 바인딩은 ViewerBridge의 내부 의존성이다. 앱·검증 실행 파일에는 raw ticket/포인터 복사 API를 노출하지 않는다. Swift 소유 버퍼는 복사가 끝나기 전 외부에 공개하지 않고 이후 불변으로 유지한다. GPU가 쓰는 버퍼에 덮어쓰는 API는 제공하지 않는다.
- Swift 복사본은 별도 budget를 예약하고 마지막 소유 객체가 해제될 때 반환한다. 원본 Rust handle과 Swift 소유 복사본을 각각 계수한다. 데이터 접근은 소유 객체 수명 안의 읽기용 closure만 제공한다.
- 파일 준비와 큰 복사는 Swift `Task.detached`에서 실행한다. UI는 현재 shell을 유지한다. 전체 요청 generation·취소·GPU 완료 순서는 후속 표시 통합에서 검증한다.

## 좁은 입력 adapter의 범위

실제 Part 10 파일의 legacy CT/MR/Secondary Capture 단일 프레임을 받는다. native Explicit LE/Implicit LE/Explicit BE와 8·16비트 회색조의 BitsStored/HighBit·부호·padding 범위·단순 rescale을 해석한다. RGB는 Secondary Capture의 unsigned RGB8 planar 0만 RGBA로 바꾼다. BE의 8비트 OW는 oracle 미확보로 거부한다. 컬러 ICC/색공간·LUT, Modality/VOI/Presentation LUT·RWVM·Functional Groups·Enhanced·다중 프레임·압축은 제한 오류다. VOI/극성·단위·종횡비·source/generation은 아직 전달하지 않으므로 UI 표시 capability를 켜지 않는다. non-finite 및 유한 F64→F32 overflow는 명시적으로 Unsupported다.

파일은 nonblocking open 후 같은 handle에서 regular-file 확인과 32 MiB bounded read를 수행한다. FIFO와 입력 증가 경계도 시험한다. parser/codec의 전체 메모리·중첩 한도와 source가 읽는 도중 수정되는 경우의 일관성은 이 계약의 완료 범위가 아니다.

## 검증

최종 환경: Apple M5/16 GiB, macOS **27.0.1(26A434)**, Rust 1.98.1, Swift 6.4 CLT, deployment target 27.0. UniFFI 0.32.2·dicom-rs 0.10.0·libc 0.2.189를 lock으로 고정했다. 결과는 [P1-pixel-contract.json](results/P1-pixel-contract.json)이다.

| 실행·범위 | 기대/실제 | 상태 |
| --- | --- | --- |
| `bash scripts/check.sh` 및 `--release` | 각 profile fmt/clippy·locked Rust/Swift build, core 16+FFI 6, Swift 18, bootstrap·합성 원본 hash 보존 | pass |
| Rust frame | 크기/overflow·mask·F32 범위, 예산 선예약·동시 예약·마지막 owner, 실패 주입/샘플 오류/panic rollback | pass |
| Rust FFI | 정확 길이·error 시 목적지 미변경, no mask·만료/비재사용 ticket, evict/close/진행 중 copy의 charge, copy/drop 경합 100회 | pass |
| Swift 실제 native 입력 | Gray LE/BE/implicit 3×2 → F32 `[0,-12,-10,-8,2038,4084]`, mask `[0,1,1,1,1,1]`, Rust/Swift 각각 30 bytes. RGB 2×2 → RGBA literal 16 bytes | pass |
| Swift 수명/제한 | evict/close 뒤 retained handle copy와 원본 해제 뒤 Swift copy 유효. 제한 초과·별칭·동시 복사·마지막 owner 해제와 재수용. MainActor 호출→비주 thread guard가 있는 detached 준비/복사 | pass |
| 입력 오류 | multiframe/compressed/Enhanced/F32 overflow Unsupported; index InvalidArgument; malformed/missing DecodeFailed; 32 MiB+1 ResourceLimit. 실패 뒤 live/cache/active=0, reason에 원문 path 없음 | pass |
| FIFO/읽기 경계·native 범위 | writer 없는 FIFO 즉시 거부, 관찰 크기보다 커지는 입력 제한, CT/MR RGB 거부, 8bit OB/implicit OW·유효 비트/padding range | pass (Rust core) |
| debug/release `ViewerApp --ui-smoke-test` | 창·메뉴·열기 비활성·Command Q·마지막 창 닫기 종료 | pass (자동 검사; 시각 재관찰 아님) |
| 독립 fixture parsing | pydicom 3.0.2로 기존 합성 4개 read-only; 부호 배열/RGB가 literal과 일치 | pass (main·reviewer 각각 확인) |
| VOI·Metal/GPU·전체 codec·generation/cancel·engine/parser/RSS·P5 | 후속 범위 | not-run |

Rust 할당 실패는 시험 allocator에 오류를 주입한 rollback 검증이며 실제 시스템 OOM을 유도하지 않았다. Swift의 실제 malloc 실패 주입은 not-run이다. 예산 수치·해제는 payload 계측이며 RSS 누수나 성능 합격으로 확대하지 않는다. 전체 제품 T-11/T-13 합격도 별도다.

## 통합 중 수정과 독립 검토

초기 Rust 컴파일의 header length/JoinHandle 오류, Swift import access와 생성 error enum PascalCase 불일치, FFI lint를 수정했다. 개발용 wrapper가 SIGKILL 9로 종료되고 bundle signature 검증이 실패해 빌드에서 새 실행파일 inode 교체·로컬 ad-hoc 서명·strict verify를 수행하도록 보완했다. 수정 후 최종 debug/release 앱·계약·UI smoke가 pass했다. CLT의 존재하지 않는 developer 검색 경로 경고는 남으며 빌드·링크 실패는 아니다. 설치·공증 합격으로 취급하지 않는다.

`P1-PIXEL-REVIEW`는 producer/consumer/C/빌드/문서와 최종 증거를 읽기 전용으로 검토했다. 필수 수정 결함 0. source 28·generated 3·fixture 10·binary 4·원시 로그 hash 전부 대조, strict signature·arm64/minos27/static Rust 링크와 독립 pydicom readback을 직접 확인했다. reviewer는 재빌드·앱 실행·fixture 생성/수정을 하지 않았다. CUA 시각 재관찰과 후속 범위의 not-run을 보존했다.

## 인수인계

- 모든 배정 종료·작성권 반환. `codex/p1-foundation` / HEAD `ca9e8b8`; 이전 골격과 이번 픽셀 계약 변경은 미커밋, commit/push 없음. P0 tracked 소스·결과 변경 없음.
- 변경: core frame/native·libc direct dependency, FFI session/handle/ticket/C copy, Swift PixelFrames/CLI, handwritten C module·Package·기존 bootstrap internal import, fixture 생성·check/build, API/architecture/ADR·진행 문서·결과 JSON.
- 재현: `bash scripts/check.sh`, `bash scripts/check.sh --release`; GUI shell 회귀를 함께 실행하려면 `--ui` 추가. 생성 fixture·bindings·binary·원시 로그는 캐시/ignored 경로다. synthetic source 파일은 변경하지 않는다.
- 다음: [P1 계획](P1-single-frame.md)의 묶음 3. VOI·극성·단위·종횡비·진단·source/request 계약을 추가하고 비동기 파일 열기·CPU 기준·Metal 표시를 연결한다. 현재 앱 열기 비활성·bootstrap false를 새 표시 capability 구현 전까지 유지한다.
