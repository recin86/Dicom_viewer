# P0 기술·자료 확인 계획

작성: 2026-09-30 (Asia/Seoul) · 최초 작성 AI: Claude (Cowork) · CODEC 조정: Codex / P0-CODEC-20260930 · 종료 조정: Claude (Cowork) / P0-CLOSE-20260930 · 상태: **P0 완료 (2026-09-30)**

이 문서는 [개발·검증 계획](../06-development-and-validation.md)의 P0를 실제 작업으로 나눈 계획이다. 계획과 실제 실행 증거를 구분하며, 아래 상태는 실행 결과 절을 기준으로 읽는다.

## 목적과 기준 상태

P0의 질문은 다음 네 가지다.

1. 사용자의 Mac에서 Rust 코어를 빌드해 Swift가 호출하고, 큰 픽셀 버퍼를 왕복할 수 있는가 (OQ-02).
2. dicom-rs의 어떤 버전·feature 조합이 v0.1 Transfer Syntax를 실제로 디코딩하며, Modality/VOI 변환 경계를 통제할 수 있는가 (OQ-03).
3. 대표 자료의 SOP Class·Transfer Syntax·Enhanced 비중은 어떠한가 (OQ-03, OQ-04).
4. 지원 OS/CPU, 성능 기준 환경, 배포 방향을 무엇으로 기록할 것인가 (OQ-01, OQ-05, OQ-06).

| 항목 | 값 |
| --- | --- |
| 기준 브랜치·commit | `main`, `e4a9544` |
| 작성 시 미커밋 상태 | 수정 5개(AGENTS.md, README.md, docs/07, dicom-orchestrate SKILL.md·stage-plan.md), 신규 PROGRESS.md·docs/implementation/ — 이전 작업(SETUP-GIT-HANDOFF)의 변경이며 이 계획이 되돌리지 않음 |
| 원격 | 미연결 |
| 관련 문서 | [README OQ 목록](../../README.md), [DICOM 지원 명세](../03-dicom-support.md)의 Transfer Syntax 절, [아키텍처](../02-system-architecture.md)의 코어 경계·픽셀 경계, [API](../04-core-api-and-data-model.md)의 픽셀 전달·메모리 소유권 |
| 관련 ADR | [0001](../adr/0001-rust-core-swift-app.md) 채택 전제, [0002](../adr/0002-uniffi-and-pixel-buffers.md)·[0003](../adr/0003-metal-and-frame-model.md) 제안 상태 |
| 관련 시험 | T-03, T-04(변환 중복), T-11(버퍼 수명), T-20(빌드) — P0에서는 사전 실험이며 정식 합격 판정이 아님 |

## 환경과 의존성

**확인된 사실:** 작업 폴더는 처음에 OneDrive 동기화 폴더 안에 있었고, 2026-09-30 사용자가 로컬 `~/Documents/Dicom_viewer`로 옮겼다. 이후 기기 간 공유는 OneDrive 대신 GitHub 원격으로 한다. Cowork 세션의 셸은 격리된 Linux VM이라 Mac의 Xcode·Rust 상태를 직접 확인하지 못했다.

**Cowork 기기 정보로 확인 (2026-09-30):** 대상 Mac은 darwin/arm64(Apple Silicon MacBook Air)이다. 홈 폴더에 `.rustup`, `.cargo`, `.homebrew`가 있어 Rust와 Homebrew가 설치된 것으로 보이나 버전과 동작은 미확인이다.

**사용자 확인 (2026-09-30):** Intel Mac 지원 안 함. 현재 DICOM 자료 없음. Xcode와 Apple 개발자 계정 없음. App Store 등록 계획 없음. 원격 저장소 `https://github.com/recin86/Dicom_viewer` (연결 시 비어 있음 확인).

**미확인 (P0-ENV에서 기록):** macOS 버전, 칩 세대, 메모리, GPU, 화면 해상도·배율, Xcode·Swift·Rust 버전, 설치된 Rust target.

OneDrive 대응 규칙 (2026-09-30 폴더 이동 전까지 적용, 기록용으로 남김. 이동 후에도 빌드 산출물은 저장소 밖 `~/Library/Caches/dicom-viewer/`에 두는 run.sh 기본값을 유지):

- Rust 빌드 산출물은 OneDrive 밖에 둔다. 예: `export CARGO_TARGET_DIR="$HOME/Developer/dicom-viewer-target"` 를 셸 설정에 추가. 사용자별 절대경로가 들어가므로 `.cargo/config.toml`에 고정하지 않는다.
- Xcode DerivedData는 기본 위치(`~/Library/Developer/Xcode/DerivedData`)를 유지한다.
- 실제 DICOM 자료는 OneDrive 밖(예: `~/DICOM_samples/`)에 두고 경로로만 참조한다. 저장소 안 `/local-data/`도 OneDrive에는 동기화되므로 실제 자료 위치로 쓰지 않는다.
- 원격 저장소 `origin`을 연결했다(2026-09-30). 커밋을 자주 push해 `.git` 손상에 대비한다. push 범위는 사용자 지시를 따른다.

## 배정과 작성자

| Task ID | 역할 | 목적 | 수정 허용 파일/경로 | 의존 작업·계약 revision | 상태 |
| --- | --- | --- | --- | --- | --- |
| P0-ENV | 메인 | 개발 환경 조사와 기준 장비 기록 | 이 문서의 환경·실행 증거 절, `experiments/p0-env/` | 없음 | done (2026-09-30) |
| P0-DATA | dicom_fixtures (1차 수집은 메인이 수행) | 공개 시험 자료 후보와 사용 조건 조사, 사용자 로컬 자료의 통계만 수집, 합성 사례 생성 계획 | `tests/fixtures/manifest/`, `experiments/p0-data/`, `local-data/` | 없음 | done: 공개 331 수집 + 합성 38(CT 32·DX 3·US 3) fixture 준비 pass, 부족 자료 gap 기록 ([P0-closeout](P0-closeout.md), [p0-data](../../experiments/p0-data/README.md)) |
| P0-CODEC | Codex 메인 + dicom_core·dicom_fixtures·dicom_reviewer | dicom-rs 버전·feature 고정 후보, Transfer Syntax별 디코딩, 변환 경계 실험 | `experiments/p0-codec/` | P0-ENV; P0-DATA 공개 331개 + 합성 50개 | done(조사): 6개 빌드·비교·제한 기록, 제품 합격 아님; 아래 최종 증거 |
| P0-FFI | 메인 (공유 FFI 작성권) | UniFFI + 정적 라이브러리 + Swift 호출, 큰 bytes 왕복·async·panic·취소 실험 | `experiments/p0-ffi/` | P0-ENV | done: 1차 실험 + 계약 실험(P0-FFI-CONTRACT) Mac pass 11/fail 0 ([p0-ffi-contract](../../experiments/p0-ffi-contract/README.md)); 레코드 경로 누적 원인은 미확정이나 채택 경로에 해당 없음 |
| P0-DIST | 메인 | 배포 방향(OQ-05) 기록 | 이 문서의 판단 절 | P0-ENV | done(방향 기록): 사용자 결정 유지, 다른 Mac 배포 검증은 P5 |
| P0-REVIEW | dicom_reviewer | P0 결과와 OQ 결론의 증거 검토 | 읽기 전용 | 위 작업 완료 | done: 독립 reviewer 조건부 완료 → F1 재실행으로 조건 충족 ([P0-closeout](P0-closeout.md)) |

실행 순서: P0-ENV → (P0-DATA, P0-CODEC, P0-FFI 병렬, 최대 3개) → P0-DIST → P0-REVIEW → OQ 확정과 문서 반영.

`experiments/`는 [아키텍처](../02-system-architecture.md)의 예상 코드 배치에 없는 **P0 전용 일회성 실험 폴더**다. 여기의 코드를 그대로 `crates/`나 `macos/`로 옮겨 제품 경계로 굳히지 않는다 (docs/06 P0 원칙).

### P0-ENV · 환경 조사

Mac의 터미널에서 실행하고 출력 전체를 아래 실행 증거에 붙인다.

```sh
sw_vers
uname -m
sysctl -n machdep.cpu.brand_string hw.memsize
system_profiler SPDisplaysDataType | grep -E "Chipset|Resolution|Metal"
xcode-select -p && xcodebuild -version
swift --version
rustup --version && rustc --version && cargo --version
rustup target list --installed
python3 --version
```

Rust가 없으면 rustup으로 설치하고 `aarch64-apple-darwin` target만 확인한다 (Intel 제외).

Xcode가 없으므로 Command Line Tools(CLT) 설치 여부와 다음을 확인한다: `swift build`로 AppKit/SwiftUI/MetalKit을 링크하는 실행 파일 빌드, `xcrun -f metal`의 존재(CLT에는 오프라인 Metal 컴파일러가 없을 가능성이 높음), `codesign -s -` ad-hoc 서명. 오프라인 Metal 컴파일러가 없으면 P1까지는 shader를 앱 실행 시 `MTLDevice.makeLibrary(source:options:)`로 컴파일하는 경로를 쓰고, `.app` 번들은 SwiftPM 산출물 + Info.plist로 스크립트 조립한다. 무료 Xcode(개발자 계정 불필요) 설치는 Metal 디버깅·Instruments가 필요해질 때 다시 검토한다.

완료 기준: 기준 장비 1대의 사양 기록(OQ-06 초안), 도구 버전 기록, Intel 지원 검토 여부에 필요한 사용자 입력 확인.

### P0-DATA · 대표 자료

사용자 자료가 없으므로(2026-09-30) **합성 자료 우선**으로 진행한다. 합성 fixture는 pydicom 등으로 생성하고 기대값을 독립 계산한다.

1. 재배포 조건이 명시된 공개 자료 후보를 조사한다. 후보: dicom-rs 저장소 시험 파일, pydicom-data, GDCM/DCMTK 시험 자료, NEMA 샘플, TCIA 공개 컬렉션. 각각 라이선스·재배포 가능 여부를 기록하고, 확인 전에는 저장소에 넣지 않는다.
2. (현재 해당 없음) 이후 사용자 로컬 자료가 생기면 **파일을 복사하지 않고** OneDrive 밖 위치에서 읽기 전용 스크립트로 SOP Class, Transfer Syntax, Modality, Photometric Interpretation, Bits Allocated/Stored, 프레임 수, Enhanced 여부의 분포만 집계한다. 환자 정보·경로·UID는 출력하지 않는다.
3. [최소 자료 구성](../06-development-and-validation.md) 표 대비 빈칸 목록과 합성 fixture 생성 계획(docs/06 합성 사례 표 기준)을 작성한다.

완료 기준: fixture manifest 초안(ID, 출처, 조건, SHA-256, SOP/TS, 기대 기능), 합성 fixture 생성 스크립트 계획, OQ-03·OQ-04 판단 근거. 실제 자료 분포가 없으므로 OQ-03·OQ-04는 공개 자료와 일반적 사용 빈도를 근거로 잠정 결정하고, 자료가 생기면 재검토한다.

### P0-CODEC · 디코더 실험

1. 2026-09-30 시점 최신 dicom-rs(`dicom-object`, `dicom-pixeldata`, `dicom-transfer-syntax-registry`) 버전과 feature를 확인해 후보 조합을 고정한다.
2. 기본 조합(native, deflate, rle, jpeg)과 평가 조합(charls, openjp2 또는 openjpeg-sys)을 각각 macOS에서 빌드한다. C/C++ 의존성의 빌드 요구 사항(cmake, clang)과 라이선스를 기록한다.
3. Transfer Syntax별로 디코딩한 픽셀을 독립 참조(pydicom + pylibjpeg 또는 DCMTK/GDCM)와 비교한다. lossless는 전 픽셀 일치, lossy는 참조 대비 차이를 기록한다.
4. 변환 경계: 음수 intercept·비단위 slope 자료에서 선택한 API/옵션이 저장 값·Modality 적용 값·VOI 적용 값 중 무엇을 반환하는지 확인하고, rescale 중복이 없는 호출 방법을 기록한다.
5. 압축 multi-frame에서 빈 Basic Offset Table·다중 fragment 프레임의 프레임 단위 디코딩 가능 여부와 메모리 사용을 기록한다.

완료 기준: 고정할 버전·feature 목록, TS별 pass/fail 표, JPEG-LS/JPEG 2000 v0.1 포함 여부 권고(OQ-03), 변환 호출 규칙.

### P0-FFI · Rust–Swift 연결 실험

1. 최신 UniFFI 버전을 확인하고 생성기·런타임 버전을 함께 고정한다.
2. 최소 Rust crate(`staticlib`)에 다음 API를 만든다: 버전 문자열, 구조화한 오류 반환, `async` 함수, W×H 크기의 `Vec<u8>` 반환, 의도적 panic, 취소 가능한 긴 작업.
3. 생성된 Swift 바인딩을 SwiftPM 실행 파일에서 호출한다(Xcode 없음). Rust 정적 라이브러리는 SwiftPM의 system library target 또는 linker 설정으로 연결하고, 이 방식이 이후 앱 번들 빌드에도 쓰일 수 있는지 확인한다.
4. 512×512 GrayF32(1 MiB), 2048×2048 RGBA8(16 MiB), 4096×4096 GrayF32(64 MiB)를 30회 이상 반환해 p50/p95 시간, 복사 횟수(생성 코드 확인), peak memory를 기록한다. release 빌드로 측정한다. Instruments가 없으므로 peak memory는 `/usr/bin/time -l`의 maximum resident set size와 프로세스 내 계측으로 기록한다.
5. 확인 항목: bytes가 Swift에서 어떤 타입(`Data` 등)이 되는지, async가 MainActor를 막지 않는지, panic이 unwind로 앱을 죽이지 않고 오류가 되는지, 반환 payload가 Rust 쪽 해제 후에도 유효한지.

완료 기준: OQ-02 결정(UniFFI 채택 또는 대안), ADR 0002 상태 갱신 근거, 큰 버퍼 비용 수치.

### P0-DIST · 배포 방향

**방향 확정 (2026-09-30, 사용자):** App Store 등록 안 함, 유료 개발자 계정 없음. 따라서 본인 Mac에서 직접 빌드한 `.app`을 ad-hoc 서명(`codesign -s -`)으로 실행한다. App Sandbox는 요구되지 않으므로 사용하지 않는 작업안이며, 이 경우 security-scoped bookmark 없이 일반 파일 경로로 접근한다(ADR 0004·아키텍처의 bookmark 관련 문장은 조건부로 유지). notarization은 대상 아님. 다른 Mac에 복사해 실행하는 경우의 Gatekeeper 동작은 필요할 때 P5에서 확인한다.

## 기준 환경 (OQ-06 초안, 2026-09-30 P0-ENV)

| 항목 | 값 |
| --- | --- |
| 기기 | MacBook Air, Apple M5 (성능 4 + 효율 6 코어, GPU 8코어, Metal 4), 메모리 16 GiB, unified memory |
| OS | macOS 27.0 (26A428) |
| 화면 | 외부 3840×2160, UI 1920×1080 @ 60 Hz (배율 2×) |
| Apple 도구 | Xcode 없음. Command Line Tools 27.0, SDK macOS 27.0, Swift 6.4, codesign 있음, `metal`/`metallib` 없음 |
| Rust | rustup 1.29.0, stable rustc/cargo 1.95.0 (2026-04), target aarch64-apple-darwin, CARGO_TARGET_DIR 미설정 |
| 기타 | Homebrew 7.0.6, git 2.54.0, 시스템 python3 3.9.6, cmake 없음 |

후속 조치 (P0-CODEC/FFI 시작 전):

- `rustup update stable`로 최신 stable 확인 후 버전 고정 (1.95.0은 약 5개월 전 릴리스).
- (폴더 이동으로 해당 없음) 셸 설정에 `CARGO_TARGET_DIR`를 OneDrive 밖 경로로 지정.
- C/C++ 코덱(charls, openjpeg-sys) 빌드에 cmake가 필요한지 확인하고 필요하면 `brew install cmake`.
- 시스템 python3 3.9는 pydicom 3.x(3.10+)를 못 쓸 수 있음. 참조 디코딩은 Cowork VM(python 3.10, pydicom 3.0.2)에서 하거나 Homebrew python을 사용.
- 성능 기준은 이 기기 1대로 시작. 16 GiB라 캐시 기본 예산(CPU 512 MiB, GPU 256 MiB) 제안은 그대로 출발점으로 둔다.

## 판단과 계약 변경

| 날짜 | 질문 | 결정과 근거 | 영향 문서 |
| --- | --- | --- | --- |
| 2026-09-30 | OQ-01 CPU | Apple Silicon만 지원, Intel 제외 (사용자 결정) | README OQ 표; docs/06의 Intel 관련 문장은 조건부라 유지 |
| 2026-09-30 | OQ-05 배포 | App Store·유료 계정 없이 개인용 직접 빌드, ad-hoc 서명, Sandbox 미사용 작업안 (사용자 결정) | README OQ 표 |
| 2026-09-30 | 개발 도구 | Xcode 없이 CLT + SwiftPM으로 시작, 필요 시 무료 Xcode 재검토 (사용자 환경). P0-ENV에서 CLT만으로 Swift+AppKit+Metal 빌드와 런타임 shader 컴파일 확인, 오프라인 `metal` 컴파일러 없음 확인 → P1 shader는 런타임 컴파일 경로 | 이 문서 P0-ENV·P0-FFI, 이후 ADR 0003 검토 |
| 2026-09-30 | OQ-01 최소 macOS | 개발 기준 macOS 27.0. 더 낮은 버전 지원은 확인할 기기가 없어 현재는 macOS 27 이상으로 두는 작업안 (P0 종료 시 확정) | README OQ 표 |
| 2026-09-30 | OQ-02 Rust–Swift 연결 | **UniFFI 0.32.2 + Rust 정적 라이브러리 + SwiftPM(CLT) 채택 권고.** Xcode 없이 빌드·정적 링크 성공, 오류·panic·async·수명 계약 충족. 512×512 CT 프레임 전달 0.3 ms로 목표 대비 무시 가능. 64 MiB급은 34~51 ms라 대형 DX·cine 대량 전달 시 복사 비용 고려. P0-REVIEW 후 ADR 0002를 채택으로 변경 | ADR 0002, README OQ 표 |
| 2026-09-30 | 픽셀 전달 경로 (P0-FFI 근거) | **권고: 픽셀은 레코드 안 `Vec<u8>` 반환 대신, Rust가 디코딩 프레임을 객체로 보유하고 Swift가 소유한 대상 버퍼에 Rust가 1회 복사하는 방식.** 레코드 경로는 1 MiB급에서는 문제없으나 16 MiB 이상에서 호출당 프레임 크기만큼 footprint가 쌓이고 순간 복사본이 Rust 3장+Swift 3장 생김. 대안은 모든 크기에서 footprint 일정, 전달 15~20배 빠름. 대상 버퍼는 P1에서 Metal 공유 버퍼(Apple Silicon unified memory)로 두면 GPU까지 복사 1회가 될 수 있음. UniFFI 0.32.2에는 안전한 `&mut [u8]` 인자가 없어 실험은 주소(u64)+길이로 전달했고, 동기 호출 동안 버퍼 유효를 보장하는 계약이 필요. UniFFI가 `&mut [u8]`를 릴리스하면 같은 의미로 교체. 메타데이터·제어 API는 UniFFI 유지 | ADR 0002, docs/04 픽셀 전달·메모리 소유권 (P0-REVIEW 후 `$dicom-ffi-contract` 절차로 반영) |
| 2026-09-30 | FFI 사용 규칙 (P0-FFI 근거) | ① 무거운 작업은 Rust async 함수 또는 Task.detached에서 호출, MainActor 동기 호출 금지 ② 취소는 Swift Task.cancel에 의존하지 않고 명시적 토큰/`cancel_request` 사용(docs/04 설계와 일치) ③ panic 가능 함수는 Result를 반환(비-Result 함수의 panic은 Swift에서 try!로 중단될 수 있음) ④ Swift→Rust 대용량은 `&[u8]` 사용 ⑤ 프레임 수신 경로의 메모리 회수를 계측 후 확정 (2026-09-30 원인 분리: Rust 누수 아님, 대형 버퍼 반복 전달 시 footprint 증가. 대안 후보: ADR 0002의 픽셀 전용 C ABI 경로(Rust 버퍼 포인터 대여 후 1회 복사/해제), UniFFI 다음 판의 `&mut [u8]` 무복사 채우기(0.32.2 미포함, main 브랜치 CHANGELOG에 있음)) | docs/02·04 반영 후보 |
| 2026-09-30 | OQ-03 코덱 후보 | **dicom-rs 0.10.0 + baseline + charls + openjpeg-sys 권고.** Mac에서 6개 조합 빌드와 381개씩 비교 완료. JPEG-LS/J2K 정상 사례를 확인했으나 저장 값·컬러·프레임 경계 제한이 남아 제품 통합 보완 필요. OQ 최종 채택은 전체 P0 검토 후 | [CODEC 보고서](../../experiments/p0-codec/README.md); README OQ·docs/03 반영은 전체 검토 후 |
| 2026-09-30 | **OQ-01~04 확정 (P0 종료)** | OQ-01: Apple Silicon·최소 macOS 27.0(사용자 확인). OQ-02: UniFFI 0.32.2 + 정적 라이브러리 + SwiftPM, 픽셀은 타입 있는 C 복사 함수와 Swift 래퍼(ADR 0002 채택). OQ-03: baseline + charls + openjpeg-sys, 제한은 P1 adapter 과제. OQ-04: Enhanced CT/MR v0.2 후보 유지, v0.1은 식별·제한 | README OQ 표, ADR 0002, docs/02·03·04·06, [P0-closeout](P0-closeout.md) |

그 밖의 OQ 결론은 날짜·증거·선택 이유·영향 문서와 함께 여기에 추가한 뒤 README OQ 표와 해당 ADR을 갱신한다.

## 실행 증거

| T ID / 사례 | 요구사항 | Build ID / 환경 / fixture | 실행 명령 | 기대값·실제값과 증거 위치 | 결과·이유 |
| --- | --- | --- | --- | --- | --- |
| P0-ENV 환경 기록 | QR-06 | 사용자 Mac (아래 기준 환경) | 사용자가 `bash experiments/p0-env/check-env.sh` 실행 (Cowork의 터미널 제어는 클릭 전용이라 직접 실행 불가) | 전체 출력: `experiments/p0-env/env-report.txt` | pass: 환경 기록 완료 |
| P0-ENV Swift·Metal 런타임 | QR-06 | 같은 환경, CLT만 | 위 스크립트의 swiftc 시험 | Metal device Apple M5 인식, 런타임 shader 컴파일 OK, AppKit 링크 OK; `xcrun -f metal` 없음 | pass: Xcode 없이 CLT로 Swift+Metal 빌드 가능 (오프라인 shader 컴파일은 불가) |
| P0-DATA 공개 자료 1차 수집 | FR-03 (T-03 준비) | Cowork VM, pydicom 3.0.2, pydicom-data main(depth 1) | `local-data/pydicom/`에 복사 후 목록 스크립트 실행 | 180개 모두 메타데이터 읽기 ok; TS 16종(HTJ2K 포함), CT/MR/CR/US/US-MF/Enhanced MR·CT/SC/SEG 등; 목록 CSV와 README는 `local-data/pydicom/` (Git 제외) | done(수집만): 픽셀 디코딩·기대값 비교는 P0-CODEC |
| P0-DATA CT 시리즈 수집 | FR-01, FR-04 (T-01·T-06 준비) | Cowork VM, GitHub raw | neurolabusc/dcm_qa_ct의 In/GE, In/Philips/S21610만 다운로드 | GE 28장(tilt +18.5°, 간격 1.08~7.00 mm), Philips 5개 시리즈(확장자 없음, tilt ±, localizer·SC·비영상 포함); 목록 ver1.1 CSV와 `local-data/README.md` | done(수집만) |
| P0-CODEC TS별 디코딩 | FR-03, QR-01 (T-03 사전) | M5/macOS 27.0, Rust 1.98.1, dicom-rs 0.10.0, 6 feature 조합, 공개 331+합성 50 | `bash experiments/p0-codec/run.sh all` | TS별·개별 사례·소스 및 binary hash: `experiments/p0-codec/results/`; 최종 표는 CODEC 보고서 | build pass; 비교는 fail/not-run을 보존, exit 1 |
| P0-CODEC 변환 중복 | QR-01 (T-04 사전) | 같은 환경, slope=2.5/intercept=-1024.5 합성, stored/Modality 독립 출력 | 같은 명령 | 합성 Modality 전 픽셀 일치. None 저장 값의 signed·unused bits 불일치, public Modality 제한 및 FG oracle not-run을 별도 기록 | 혼합: 합성 rescale pass, 저장 값·일부 public transform fail, FG Modality not-run |
| P0-FFI 버퍼 왕복 | QR-02, QR-03 (T-11 사전) | M5/macOS 27.0, rustc(업데이트 후 stable), uniffi 0.32.2, Swift 6.4 CLT, release, 정적 링크(otool에 libp0ffi 없음) | `bash experiments/p0-ffi/run.sh` | Rust→Swift ffi 비용 p50/p95: 1 MiB 0.33/0.35 ms, 16 MiB 7.27/7.42 ms, 64 MiB 34.19/51.43 ms (약 2 GB/s, fill 제외); 길이·stride·checksum·샘플 픽셀 일치. Swift→Rust 64 MiB: Vec<u8> 67 ms, &[u8] 1 ms. 캐시 비우기·객체 해제 후 payload 유효. 증거 `experiments/p0-ffi/results/` | pass |
| P0-FFI 메모리 | QR-03 | 같은 환경 | 같은 스크립트 | 64 MiB × 33회 구간에서 footprint 568→2715 MiB, peak footprint 2.95 GB; autoreleasepool 안의 16 MiB × 200회 뒤 1082 MiB로 감소했으나 살아 있는 프레임이 없는데도 1 GB 잔류. 반환 Data/중간 복사본의 해제 시점 문제로 추정 | fail(조사 필요): 캐시 예산 계측 전에 원인 확인 |
| P0-FFI 메모리 후속 | QR-03 | 같은 환경, 변형별 별도 프로세스, 64 MiB GrayF32 | `bash experiments/p0-ffi/run.sh mem` | 1회 수신 순간 peak = 프레임 3.04장, 호출 후에도 3장 유지. Rust 내부만 20회 = 1장 유지(증가 없음). 수신 20회(레코드/바이트, autoreleasepool 유무 무관) = 22장, 1초 대기·malloc pressure relief 후에도 그대로(relief 0 MiB). → autorelease·할당기 캐시가 아니라 **호출당 약 1프레임씩 해제되지 않음**. 증거 `experiments/p0-ffi/results/p0-ffi-mem.txt` | fail: 다음 단계로 Rust 전역 할당 계수기로 RustBuffer 해제 여부를 확인해 Rust/Swift 쪽을 가른다 |
| P0-FFI 메모리 원인 분리 | QR-03 | 같은 환경, Rust 전역 할당 계수기 추가, Swift 단독 모사 변형 | `bash experiments/p0-ffi/run.sh mem` | **Rust 누수 아님**: 모든 변형에서 Rust 할당 수 = 해제 수, 살아 있는 Rust 메모리 증가 0. 1회 호출 중 Rust 쪽 순간 peak 192 MiB(프레임 3장: 채우기 Vec + 직렬화 버퍼 등). 생성 코드의 Swift 복사 과정(Data(bytesNoCopy)→[UInt8]→Data)을 Rust 없이 20회 모사하면 3장에서 증가 없음. 증가(20회 후 22장)는 Rust·Swift가 번갈아 64 MiB급 버퍼를 할당·해제할 때만 나타나고, 한 번은 1초 뒤 14장으로 줄어듦 → 살아 있는 객체 누수보다 대형 블록의 해제 지연·재사용 실패(할당기 동작)로 추정, 단 완전히 증명되지는 않음 | 부분 해결: Rust 측 해제 확인. 실사용 크기(1~16 MiB) 반복 시 증가 여부로 영향 판단 필요 |
| P0-FFI 실사용 크기 | QR-03, T-11 사전 | 같은 환경 | `bash experiments/p0-ffi/run.sh real` (1차) | 1 MiB CT×300: footprint 6.3 MiB에서 일정(기울기 0), 호출 p50 0.45 ms. 1.17 MiB US×300: 12.6 MiB 일정. CT 32장 캐시: 캐시+4.5 MiB 일정. **16 MiB×50: 호출당 16 MiB씩 증가(838 MiB), 캐시를 비워도 감소 없음.** 16 MiB 8장 캐시×100: 약 1.16 GB | CT/MR/US 크기는 pass, 대형(16 MiB) 프레임 fail → 대형 프레임용 전달 경로 필요 |
| P0-FFI 대안 경로(copy_into) | QR-02, QR-03, T-11 사전 | 같은 환경 | `bash experiments/p0-ffi/run.sh real` (2차) | Rust가 프레임을 객체로 보유하고 Swift가 할당한 버퍼 주소로 1회 복사(`FrameBuffer.copy_into`). 전달 시간 p50(대상 버퍼 할당 포함): 1 MiB 0.02 ms(기존 0.33), 16 MiB 0.45 ms(기존 약 7~10), 64 MiB 1.86 ms(기존 34). footprint: 16 MiB×50 38 MiB 일정(기존 840 MiB 증가), 버퍼 재사용 34 MiB, 16 MiB 8장 캐시×100 198 MiB 일정(기존 1.16 GB), 64 MiB×20 146 MiB 일정. 모든 변형 checksum 일치, Rust 살아 있는 메모리 증가 0. 같은 실행에서 기존 경로의 16 MiB 증가 재현됨 | pass |
| P0-FFI panic·async·취소 | QR-02 (T-11·T-12 사전) | 같은 환경 | 같은 스크립트 | 구조화 오류 3종 전달; Result 함수의 Rust panic → Swift `UniffiInternalError.rustPanic`(fileprivate 타입) 전달, 이후 라이브러리 정상. async Rust 함수 대기 중 MainActor 최대 공백 4 ms, MainActor에서 동기 300 ms 호출 시 공백 303 ms, Task.detached 동기 호출 3 ms. 명시적 CancelToken 취소 지연 8.6 ms, Swift Task.cancel()은 Rust 작업에 전달 안 됨(549 ms 후 정상 완료) | pass |

## 독립 리뷰와 최종 상태

P0-CODEC 독립 리뷰(Codex 세션)와 P0 전체 종료 리뷰(Claude 세션, 독립 reviewer 서브에이전트)를 실행했다. 전체 리뷰는 차단 결함 없이 조건부 완료로 판정했고, 조건(C08 결과 재생성)과 반영 사항은 [P0-closeout](P0-closeout.md)에 있다. **P0 완료 (2026-09-30).** P0 종료 조건(docs/06): 대표 자료 manifest, 의존성 버전·feature 고정, 대상 Mac에서 Rust 호출과 큰 bytes 왕복, OQ-01~04 확정, OQ-05 방향과 OQ-06 기준 환경 기록. 제품 지원이나 릴리스 합격을 뜻하지 않으며 남는 not-run 항목은 P0-closeout에 있다.

## 필요한 사용자 입력

2026-09-30에 모두 답변받음 (위 환경 절 참조). 남은 입력: 현재 미커밋 변경의 커밋·push 범위.

## 이전 인수인계 · Claude 종료 시점

2026-09-30 Claude(Cowork) 조정 종료. 사용자가 이후 작업을 Codex로 진행한다. 실행 중인 작업과 미커밋 변경은 없다(인수인계 커밋 기준).

- 완료: P0-ENV(기준 환경 기록), P0-FFI(연결·오류·async·취소·메모리·대안 픽셀 경로), P0-DATA 1차(공개 샘플 수집).
- 다음: **P0-CODEC** (위 절 참조, 자료는 `local-data/`, 목록 CSV ver1.1). 이어서 P0-DATA 합성 fixture 계획, P0-DIST 문서 반영(방향 확정), P0-REVIEW, OQ-02~04 확정, ADR 0002·docs/04에 픽셀 전달 경로 반영(`$dicom-ffi-contract`).
- 작업 방식: Cowork는 Mac 터미널에 입력할 수 없어 스크립트를 쓰고 사용자가 실행했다. Mac에서 직접 명령을 실행하는 도구(Codex 등)는 `experiments/p0-ffi/run.sh`를 바로 실행할 수 있다.
- 주의: 공개 저장소. `local-data/`와 로컬 경로가 든 로그는 커밋하지 않는다.

## Codex 인수와 현재 작성권 · P0-CODEC-20260930

- 기준: `main` / `ea7e2b351fad35a1e8871e6e21bf226739913d67`, clean working tree, origin/main보다 1 commit 앞섬. Claude 종료 기록 및 실제 상태 대조 완료. commit/push는 이 작업에서 자동 수행하지 않는다.
- 실행 환경: 실제 Apple Silicon Mac, macOS 27.0; rustc/cargo 1.98.1. 시스템 Python 3.9 대신 저장소 밖 uv Python 3.12 venv로 독립 참조 디코더와 cmake 준비.
- 메인 Codex: 중앙 진행 문서, `experiments/p0-codec/run.sh`, `README.md`, `.gitignore`, `requirements.txt`, 결과 보고서 작성·통합. 기존 p0-ffi 및 제품 API는 수정하지 않음.
- P0-CODEC-RUST / dicom_core: `experiments/p0-codec/rust/`만 작성(해당 실험 manifest·lockfile·toolchain 작성권을 명시적으로 위임). dicom-rs 정확한 버전·features 및 CLI 저장 값/Modality/개별 프레임 출력.
- P0-CODEC-REF / dicom_fixtures: `experiments/p0-codec/reference/`만 작성. 합성 파일과 독립 참조·manifest·비교 runner. 원본/참조 배열은 저장소 밖 캐시, 커밋 가능한 보고서는 fixture ID/공개 출처/SHA만 기록.
- P0-CODEC-REVIEW / dicom_reviewer: 구현과 실행 결과가 준비된 뒤 읽기 전용 독립 검토.
- 계약: P0 전용 CLI `<input> <output-prefix>`; stdout 구조화 JSON, 출력 `.stored.f64le`, `.modality.f64le`, multi-frame은 `.frame-N.f64le`(0기반). 원본 파일 변경 금지. 컬러 변환 상태는 metadata에 명시하여 raw YBR와 RGB를 잘못 비교하지 않음. 이는 제품 FFI 계약이 아님.
- 관련 기준: docs/03 픽셀·Transfer Syntax·압축 프레임; docs/06 P0 및 T-03/T-04/T-05/T-13 사전 실험, FR-03·QR-01. 앱/GPU·정식 지원 판정은 범위 밖.

- P0-CODEC-FEATURE-FINAL: Rust 작성자 종료 후 메인이 실험 `Cargo.toml` 작성권을 회수하여 `combined-c`(baseline+charls+openjpeg-sys) feature alias만 추가. C JPEG 2000 선택 후보도 실제 JPEG-LS 동시 조합으로 통합 검증한다. 기존 producer 코드는 수정하지 않음.

## P0-CODEC 최종 증거와 인수인계 · Codex

기준 `ea7e2b3` 이후 이번 변경은 신규 `experiments/p0-codec/`와 이 문서·PROGRESS·work-log다. 제품 API/ADR·p0-ffi는 수정하지 않았다. Rust·참조 작성자는 소스를 동결했으며 마지막 통합 결과와 문서 작성은 메인이 맡았다. commit/push는 하지 않았다.

실제 버전은 [environment.json](../../experiments/p0-codec/results/environment.json), 최종 feature/라이선스/링크는 `build-*.json`, 전체 픽셀·프레임·manifest는 profile JSON, 해시 대조와 명령 결과는 [verification.json](../../experiments/p0-codec/results/verification.json)이 기준이다. Rust 1.98.1과 Python 3.12.13을 고정했고 CMake 4.4.3은 캐시의 격리 venv에 설치했다. 기존 ENV 절의 Rust 1.95.0·CMake 미설치는 당시 기록이다. CharLS는 CMake C++ 정적 빌드, C OpenJPEG는 cc 정적 빌드이며 외부 codec dylib이 없다.

- 공개 331 + 합성 50(정상 42·손상 8), 각 381개를 6개 feature 조합에서 비교했다. 전체 결과 표와 TS별 표는 [CODEC 보고서](../../experiments/p0-codec/README.md)에 있다. 모든 원본 전후 SHA·목록 SHA 유지, 6개 profile 간 합성 SHA 동일. 저장 값 lossless 오차 0, lossy 최대 1 및 별도 RGB 정규화 허용치 2를 사전 정의했다.
- 저장 값/Modality/VOI 호출 규칙을 분리했다. signed 8/12비트 및 unused high bits의 `None` 출력은 정규화된 저장 값이 아니었다. 정상 rescale 합성은 일치하나 일부 공개 Modality 불일치가 남는다. 제품에서 raw 부호·유효 비트 정규화 및 변환 적용 상태가 필요하다.
- 정상 BOT/EOT·다중 fragment+BOT 합성은 일치하지만, 빈 BOT 다중 fragment JPEG-LS/J2K가 실패했다. 손상 BOT/EOT·frame count 수락과 whole 실패 뒤 selected-frame 수락도 기록했다. 컬러 planar·일부 RGB/YBR/Palette, JPEG Extended 제한을 숨기지 않았다.
- RLE 32×512×512에서 whole peak RSS 166.86~168.84 MiB, single frame 20.63~20.64 MiB(각 별도 프로세스 3회), 전 픽셀 pass. parse·f64·파일 I/O 포함이고 앱 표시·긴 cine·동시성·캐시 성능 근거로 확대하지 않는다.
- fmt·Rust 시험 3개·clippy·참조 신뢰 경계 시험 8개·Python/Bash 구문 검사·6개 release build pass. 전체 비교 명령은 제한·not-run 때문에 exit 1. 정식 T-03~05·T-13, 앱/GPU/FFI 연결·긴 cine·하위 OS는 not-run이다.

독립 reviewer가 발견한 참조 오류·안전 경계는 수정 후 재실행했다: 재실행 출력 정리, 오분류된 손상 입력, whole 오류에 가려진 selected-frame 수락, 비트 metadata LUT 과다 할당 경로, 원본/목록 hash의 강제 판정, F64 산술 허용치, Shared/PerFrame 변환의 잘못된 top-level Modality golden. FG는 저장 값·프레임 비교를 유지하고 Modality만 not-run으로 남겼다. OpenJPEG와 참조는 underlying codec을 공유하므로 공통 오류 가능성도 보고서에 기록했다. 이것은 CODEC 실험 검토이며 P0 전체 종료 검토가 아니다.

최종 reviewer는 수정된 소스·문서·6개 profile 해시·집계와 원본 331개 및 profile별 합성 50개(총 생성 300개)의 해시를 읽기 전용으로 독립 대조하고 **추가 차단 결함 없음**으로 CODEC 검토를 종료했다. 알려진 픽셀·색·프레임 실패는 P1 선행 과제로 유지한다. reviewer는 빌드·fixture 재생성 없이 최종 기록을 검토했고, 메인이 빌드·시험·통합 실행을 수행했다.

다음 작업은 P0-DATA 최소 자료 대비 부족 항목·합성 계획을 보완하고, `$dicom-ffi-contract`로 기존 copy_into 주소·버퍼 수명 계약을 검토하는 것이다. 이후 P0 전체 독립 검토 → OQ-01 최소 OS·OQ-02/03/04 확정과 README·ADR 0002·docs/04 반영 → P1 계획 순서로 진행한다. 현재 종료 시 작성권·미커밋 상태는 PROGRESS를 따른다.

## P0 종료 · Claude (Cowork) / P0-CLOSE-20260930

Codex가 P0-CLOSE 착수 중 사용량 한도로 중단한 뒤 Claude가 인수했다. DATA 보완, FFI 계약 감사·실험, OQ-01~04 확정, 전체 독립 검토를 마치고 P0를 종료했다. 실행 증거, 검토 발견과 처리, 남는 not-run 항목은 [P0-closeout](P0-closeout.md)이 기준이다. 다음은 P1 계획이다.
