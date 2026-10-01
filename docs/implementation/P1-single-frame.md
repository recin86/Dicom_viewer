# P1 한 프레임 표시 · 계획과 제품 골격

2026-09-30 (Asia/Seoul) · 조정 Codex/root · Task `P1-FOUNDATION-20260930` · 상태 **done (계획·제품 골격 완료, P1 전체는 진행 중)**.

## 목적과 기준 상태

사용자 요청은 P1 작업 계획과 제품 코드 골격(이전 보고의 1번)이다. 이번 묶음은 Rust workspace, Swift 앱과 공통 빌드 경로를 만들고, 실제 Mac에서 앱 기동과 Swift → Rust 호출을 확인한다. DICOM 파일 열기·픽셀 전달·Metal 영상 표시는 후속 작업이다. 골격 완료를 P1 종료나 DICOM 지원 합격으로 보고하지 않는다.

- 기준 `main` / `ca9e8b8c972ff6e195b52c4c7fd9163fded61920`; 착수 시 working tree clean, 원격 main은 `49b444e`(로컬 3 commit 앞섬).
- 작업 브랜치 `codex/p1-foundation`. 이전 작성 작업은 종료 기록상 없음; 기존 P0 소스·결과는 동결한다.
- 기준 문서: [구조](../02-system-architecture.md), [API](../04-core-api-and-data-model.md), [화면](../05-ui-and-interaction.md), [단계·시험](../06-development-and-validation.md). ADR 0002는 adopted, 나머지 제안 상태 유지.
- 이번 연결 검증: QR-06, T-11의 초기 메타데이터 호출과 T-20의 개발용 기동 부분만. 정식 버퍼 수명·설치 시험은 별도다.

## 환경과 의존성

현재 확인: Apple Silicon, macOS 27.0(26A428), Rust 1.98.1, Swift 6.4 Command Line Tools. Xcode 없음. Rust·Swift·native codec deployment target은 27.0으로 통일한다. 채택한 UniFFI 0.32.2와 dicom-rs 0.10.0 baseline + charls + openjpeg-sys를 workspace에 고정한다. build cache·생성 바인딩·바이너리는 Git 제외이며 로컬 캐시에 빌드한다. 공개·합성 자료는 기존 P0 manifest를 유지하며 이번에는 원본 DICOM을 읽지 않는다.

## 배정과 작성권

| Task ID | 작성자 | 목적 | 수정 허용 범위 | 의존 계약 | 상태 |
| --- | --- | --- | --- | --- | --- |
| P1-PLAN-BUILD | Codex/root | 계획·workspace·FFI·Swift package·공통 빌드·통합 | 이 문서, 중앙 문서, Cargo.toml/lock·toolchain, crates/viewer-ffi/**, macos/Package.swift·Resources/·ViewerBindings/·ViewerBridge/·viewer_ffiFFI/, scripts/**, .gitignore | BOOTSTRAP-1 | done |
| P1-CORE-SHELL | dicom_core (일반 서브에이전트에 역할 지침 전달) | 코어 식별 정보와 고정 의존성 골격 | crates/viewer-core/Cargo.toml, crates/viewer-core/src/lib.rs | BOOTSTRAP-1 | done |
| P1-APP-SHELL | macos_app (일반 서브에이전트에 역할 지침 전달) | 기본 창과 메뉴, 미구현 열기 비활성화, smoke 기동 | macos/Sources/ViewerApp/** | BOOTSTRAP-1 | done |
| P1-FOUNDATION-REVIEW | dicom_reviewer | 최종 변경·빌드·기동 증거 검토 | 읽기 전용 | BOOTSTRAP-1 | done |

서브에이전트는 추가 에이전트를 만들지 않고 중앙 문서를 수정하지 않는다. 공유 작업폴더에서 파일마다 작성자 한 명을 유지한다. main은 결과를 통합하며 commit/push는 이번 완료 조건에 포함하지 않는다.

## BOOTSTRAP-1 계약 (이번에만 구현)

- Rust core `build_info() -> BuildInfo`: `core_version: &'static str`, `dicom_rs_version: &'static str`, `frame_decode_implemented: bool`. 현재 마지막 필드는 false다. 의존성 존재를 지원 capability로 취급하지 않는다.
- FFI `bootstrap_info() -> BootstrapInfo`: `api_revision: u32`(1), `core_version: String`, `dicom_rs_version: String`, `frame_decode_implemented: bool`. 생성 이름은 Swift `bootstrapInfo()`다. 파일 I/O·픽셀·환자 태그를 받거나 반환하지 않는 짧은 동기 호출이다.
- Swift `ViewerBridge.readiness() -> ViewerReadiness`: `apiRevision: UInt32`, `coreVersion: String`, `dicomRSVersion: String`, `canOpenDicom: Bool`. raw generated 모듈 사용은 ViewerBridge 내부로 제한하고 앱은 ViewerBridge만 import한다.
- 앱은 코어 결과에 따라 파일 열기를 비활성화한다. 사용자 화면에 ABI·단계명·codec 내부 정보를 노출하지 않는다. `--smoke-test`는 창 없이 실제 FFI 결과 JSON을 출력하고 종료한다. UI 자동 확인은 별도 경로로 기본 창·메뉴·종료를 관찰한다.
- 생성 바인딩을 손으로 수정하지 않는다. 생성기는 Rust crate의 pinned UniFFI를 사용하고 static library만 Swift에 제공한다. 캐시의 이전 산출물로 현재 빌드 실패를 덮지 않는다.
- SwiftPM 실행 파일은 로컬 관찰을 위해 캐시의 개발용 `.app`에 넣는다. `local.dicomviewer.development`는 임시 식별자이고 OQ-09를 확정하지 않는다. 설치·서명·공증·다른 Mac 검증은 P5로 남는다.

## P1 후속 순서와 합격 기준

| 묶음 | 구현 범위와 의존성 | 연결 시험 | 완료 기준 |
| --- | --- | --- | --- |
| 1. 계획·골격 (이번) | workspace·고정 의존성·FFI bootstrap·Swift 기본 창·빌드 | T-11/T-20 일부 | Rust/Swift 빌드, 실제 bootstrap 왕복, 개발용 창·메뉴 기동, 독립 검토 |
| 2. 제품 픽셀 계약 | [PIXEL-1 기록](P1-pixel-contract.md): 보유 handle 예산·수명, handle API, 비공개 C copy 모듈, 프레임 한도 | T-11·T-13 일부 | **2026-10-01 완료**, debug/release 통합·독립 리뷰 pass. 실제 native 프레임의 길이·endian·mask·오류·evict/close 수명·예산 확인; 목적지는 새 불변 Swift 버퍼만 허용 |
| 3. 회색조 adapter·표시 | signedness/BitsStored, padding·Modality 1회 적용, VOI·극성, 파일 입력·비동기·Metal | T-03·04·06·12·21, T-16 일부 | 독립 golden 값과 CPU/Metal 출력·좌표 비교, 파일 오류 명시, MainActor에서 decode 없음 |
| 4. 컬러·코덱 경계 | planar·RGB/YBR/Palette, 빈 BOT 다중 fragment·손상 BOT/EOT·frame count, JPEG Extended·Modality 불일치 | T-03·05·11·13 | 지원 범위의 기준 컬러 프레임 일치, 미지원·손상 자료 정상 영상 위장 없음; 남은 CODEC 사례 처리 기록 |
| 5. 통합·P1 종료 검토 | 앱 조작·Retina·요청 오류·자원 수명과 전체 증거 회수 | docs/06의 P1 관련 시험 | 회색조·컬러 프레임, VOI·좌표·오류·MainActor 검증과 독립 검토 충족 |

합격 수치와 지원 범위는 docs/03·04·06을 참조한다. 모든 33개 P0 실패를 동일한 원인의 codec 실패로 취급하지 않는다. P2의 시리즈 탐색·cine와 P3/P4의 측정·저장은 이번에 구현하지 않는다.

## 실행 증거

Build ID `P1-FOUNDATION-20260930` / 기준 `ca9e8b8` + working tree. 환경은 위와 같다. DICOM fixture는 없음(원본을 읽지 않는 bootstrap).

| 시험 / 범위 | 실행 명령·관찰 | 기대·실제 결과 | 상태 |
| --- | --- | --- | --- |
| Rust·공통 빌드 | `bash scripts/check.sh --ui` | fmt·all-targets/all-features clippy·locked debug build exit 0; pinned codec native 의존성 포함 | pass |
| T-11 일부 / bootstrap | 같은 명령의 `--smoke-test` | Swift에서 실제 Rust API revision=1, core=0.1.0, dicom-rs=0.10.0, frame_decode_implemented=false | pass (초기 호출만) |
| T-16 일부 / 창·메뉴 | 같은 명령의 `--ui-smoke-test` | 창 visible, 앱·파일·윈도우 메뉴, 열기 button/menu disabled, Command Q selector, 실제 마지막 창 닫기 종료 모두 true | pass (기본 shell만) |
| T-20 일부 / 개발 기동 | 개발용 app-debug 앱 직접 기동, CUA 접근성·screenshot 관찰 | 빈 검사 목록·영상 영역, 명확한 준비 중 안내, 비활성 열기. 레이아웃 깨짐 없음 | pass (같은 개발 Mac만) |
| Release 빌드·기동 | `bash scripts/build.sh release`, release 앱의 `--smoke-test`·`--ui-smoke-test` | 빌드 exit 0, bootstrap 4개 값·native UI/종료 일치, 정적 Rust 링크 | pass (같은 개발 Mac만) |
| 제품 T-03~06·T-11~13·T-21 | 실제 DICOM/픽셀/GPU 경로 없음 | 후속 묶음 2~5에서 실행 | not-run |
| 정식 T-20 / 배포 | 다른 Mac·깨끗한 사용자 환경·서명·Gatekeeper 없음 | P5에서 실행 | not-run |

최초 native 의존성 빌드는 CMake가 PATH에 없어 실패했다. 기존 P0 codec venv의 CMake 4.4.3을 찾아 shared environment에 fallback을 넣고 최종 명령을 재실행해 통과했다. SwiftPM은 Xcode 없는 CLT의 존재하지 않는 developer framework/usr-lib 검색 경로 경고를 출력하지만 빌드/실행은 통과했고 전역 개발 도구 설정은 바꾸지 않았다. 원시 로그는 ignored 로컬 캐시 `~/Library/Caches/dicom-viewer/p1/`에 보관한다. Swift bindings는 pinned generator로 재생성했고 직접 수정하지 않았다. 정확한 소스·산출물 해시와 debug/release의 bootstrap·UI 기동 결과는 [P1-foundation.json](results/P1-foundation.json)에 기록했다. 기록된 소스 해시 21개는 현재 파일과 일치하며, 두 Mach-O 실행파일의 minos=27.0·arm64와 정적 Rust 링크를 확인했다.

## 독립 리뷰와 인수인계

`P1-FOUNDATION-REVIEW`는 일반 서브에이전트에 reviewer TOML·스킬·읽기 전용 배정을 전달해 실행했다. 필수 수정 결함 0. producer/generated binding/bridge/app, UniFFI 버전·checksum guard, 소스 21개·두 binary 해시, Mach-O arm64/minos=27.0, static Rust 링크, ignored 생성물·원본/P0 보존과 실제 로그를 독립 대조했다.

리뷰는 재빌드·앱 실행을 수행하지 않았다. 리뷰 시점 Mac 잠금으로 직접 CUA 재관찰은 not-run이며 main의 앞선 접근성/screenshot 관찰을 구분해 기록했다. Release smoke의 원시 stdout은 build log에 없고 결과 JSON·source/binary hash로 대조했다. main은 최종 release 앱에서 bootstrap과 UI smoke를 실제 실행해 결과 JSON에 기록했다. 전체 DICOM·픽셀/GPU·설치 검증 공백은 후속 범위이며 이번 합격으로 바꾸지 않는다.

**사용자가 요청한 묶음 1 완료.** 제품 P1 전체는 진행 중이며 다음은 묶음 2의 제품 픽셀 계약이다. 이번 골격은 캐시의 개발용 앱으로 관찰 가능하고 파일 열기는 비활성화돼 있다.

## 골격 종료 당시 인수 기록 (2026-09-30)

- 현재 작성 작업 없음. 조정 Codex/root가 기록을 종료했으며 core/app/reviewer 배정은 모두 done이다.
- `codex/p1-foundation` / HEAD `ca9e8b8`에서 모든 P1 변경은 미커밋. 기존 main의 미전송 3 commit과 이번 변경을 구분한다. commit/push는 실행하지 않았다.
- 변경: Cargo workspace·lock·toolchain, viewer-core/ffi, macos package·AppKit shell·bridge·개발용 Info.plist, scripts build/check/run/environment, ignore, README·docs02/04/06·진행 문서와 results JSON. P0 실험·결과는 변경하지 않았다.
- 재현: 프로젝트 루트에서 `bash scripts/check.sh --ui` (로그인된 GUI 세션), `bash scripts/build.sh release`, `bash scripts/run.sh`. CMake는 PATH 또는 기존 P0 venv가 필요하다. 최초 실패와 최종 pass는 위 실행 증거 참조.
- 다음 작업: BOOTSTRAP-1을 기존 초기 연결로 보존하면서 제품 FramePayload/handle API·live bytes 예산·copy 모듈/Swift 안전 래퍼 계약을 정하고 docs04·producer·consumer·T-11/T-13 시험을 같은 묶음으로 구현한다. 적용 문서·작성권을 먼저 등록하고 viewer-ffi/공통 빌드는 main 작성권을 유지한다.
- 픽셀 복사가 준비된 뒤 회색조 adapter와 실제 한 프레임 표시로 이어간다. 현재 전역 readiness bool은 프레임별 DICOM capability를 대체하지 않는다.

## 최신 후속 상태 (2026-10-01)

묶음 2의 [제품 픽셀 계약](P1-pixel-contract.md)에서 불변 frame·live 예산·native adapter·FFI handle/C copy·Swift 소유 버퍼를 구현했다. 최종 debug/release는 각각 Rust 22+Swift 18 및 bootstrap·UI smoke·원본 hash 보존 pass다. 현재 스냅샷은 [P1-pixel-contract.json](results/P1-pixel-contract.json)이며 위 foundation 결과는 당시 골격의 역사적 스냅샷이다. 개발용 앱은 새 실행파일 inode로 교체하고 로컬 ad-hoc 서명·strict verify를 수행한다.

후속 [묶음3 native 표시](P1-native-display.md)는 VOI·극성·표시 종횡비·안전 단위/diagnostics·동일 source hash·generation과 AppKit 파일 입력/Metal을 연결했다. 앱 열기는 활성화됐고 BOOTSTRAP-1 bool은 역사적 초기 호출로 false를 유지한다. 최신 debug/release는 각각 Rust35·PIXEL18·Metal26 pass이며 마지막 수동 파일 선택 창 회귀는 Mac 잠금으로 대기 중이다. 전체 P1 정식 합격은 보류한다. 골격/픽셀 계약은 `c68c920`으로 커밋했고 이번 표시 변경은 미커밋, push는 없다.


묶음4 첫 [native SC 컬러](P1-native-color.md)는 unsigned8 RGB planar0/1·YBR_FULL planar0/1·even-width YBR_FULL_422 planar0를 RGBA8로 정규화했다. 기존 공개 선언·revision/Swift/Metal 제품 소스는 보존했고 독립 literal 7종과 예상 거부 19종을 실제 prepare/copy/GPU로 확인했다. 최신 debug/release는 각각 Rust45·PIXEL18·DISPLAY26·COLOR29 pass다. 기존 DISPLAY UI 회귀는 별도 not-run이며 US/Palette/LUT/압축과 전체 P1 합격은 후속이다. [새 결과](results/P1-native-color.json)를 최신 구현의 hash 기준으로 사용한다. DISPLAY/준비 변경과 함께 미커밋이며 push는 없다.
