# DICOM Viewer 진행 상황과 인수인계

최종 갱신: 2026-10-01 (Asia/Seoul, Codex native 표시·SC 컬러 로컬 커밋, 기존 UI 회귀 대기). 이 문서는 현재 상태의 요약이다. 코드·Git 이력·실제 시험 결과와 대조해서 읽는다. 갱신하지 않은 문서나 이전 AI의 대화만으로 완료를 판단하지 않는다.

## 현재 위치

**P0·P1 골격·픽셀 계약 완료, native 표시·SC 컬러 자동 검증 완료, 실제 사용자 UI 회귀 대기.** 골격·픽셀 계약 commit은 `c68c920`이다. 사용자 지시에 따라 UI 대기와 독립적으로 묶음4 첫 SC 컬러 구현을 진행했다. unsigned8 RGB planar0/1·YBR_FULL planar0/1·even-width YBR_FULL_422 planar0를 RGBA8로 한 번 변환하며 공개 API/revision은 유지한다. 최신 debug/release 각각 Rust45·PIXEL18·DISPLAY26·COLOR29 pass, 정상 컬러7종/예상 오류19종과 FFI·Swift·Metal 수명/예산·원본 hash를 확인했다([컬러 기록](docs/implementation/P1-native-color.md), [최신 결과](docs/implementation/results/P1-native-color.json)). 독립 reviewer가 최종 저장 근거와 코드·수치를 대조했고 필수 수정 결함은 0건이다.

마지막 NSOpenPanel 후 Loading 문제를 보완했지만 Mac 잠금으로 최신 실제 파일 선택 창·Ready·실패 후 사용자 설정 복구를 관찰하지 못했다. 따라서 DISPLAY-1 완료와 P1 전체·정식 지원 판정은 보류한다([표시 기록](docs/implementation/P1-native-display.md)). 컬러 경계 준비의 fixture26·pydicom readback·오류 주입 검증은 별도 역사적 근거다. US/Palette·압축/LUT/Enhanced·다중 프레임과 전체 자원·성능 시험은 후속이며 P0 CODEC 실패·not-run은 보존한다.

| 항목 | 현재 상태 | 근거 |
| --- | --- | --- |
| 제품 설계 | 문서 0.2. OQ-01~04 확정, ADR 0002 채택(P0 종료). 나머지 ADR은 제안 | [README](README.md), [ADR](docs/adr/README.md) |
| 에이전트 구성 | 공통 지침, 역할 4개, 전용 스킬 6개 작성·검증 | [AGENTS.md](AGENTS.md), [운영 안내](docs/07-agent-development.md) |
| 역할 실행 | 초기 지침 전달 방식 4개 역할 확인; 이번 Codex 도구의 agent_type으로 dicom_core·dicom_fixtures·dicom_reviewer 실제 호출 | [작업 이력](docs/implementation/work-log.md) |
| 로컬 Git | `~/Documents/Dicom_viewer`, `codex/p1-foundation`; 골격/픽셀 계약 commit `c68c920`, native 표시·컬러준비·SC 컬러는 이번 사용자 요청의 후속 로컬 커밋에 포함(해시는 `git log -1`) | `git log --oneline`, `git status` |
| 원격 저장소 | `origin` = https://github.com/recin86/Dicom_viewer.git (공개). 2026-09-30 원격 main=`49b444e` 실제 조회, 로컬 main은 3 commit 앞섬. 2026-10-01 `c68c920` 이후 native 표시·SC 컬러 로컬 커밋 포함; push 없음 | `git ls-remote origin refs/heads/main`, `git log` |
| 구현과 자료 | native 파일 열기, Rust VOI/극성/표시 비율/입력 hash, Swift 소유 버퍼·generation·Metal·오류 복구. 합성 표시24·컬러26개와 기존 P0 자료는 캐시, 공개 331개는 ignored local-data. 최종 실제 UI 회귀는 미실행 | [최신 컬러 결과](docs/implementation/results/P1-native-color.json), [CODEC](experiments/p0-codec/README.md) |
| 현재 작업자·작성권 | P1-COLOR-20261001: core/app 구현 완료·root에 작성권 반환, 자동 통합 완료. reviewer 최종 읽기 전용 대조 완료·필수 결함0. 소스 작성 중인 작업 없음 | [컬러 구현](docs/implementation/P1-native-color.md), [표시 계획](docs/implementation/P1-native-display.md) |

## 단계별 진행

| 단계 | 상태 | 다음 완료 기준의 근거 |
| --- | --- | --- |
| 운영 준비 | 완료 | 설계·역할·스킬, 로컬 Git, 진행 문서와 인수인계 규칙 |
| P0 기술·자료 확인 | **완료 (2026-09-30)**: ENV·DATA·CODEC·FFI·FFI 계약·DIST, 전체 독립 검토, OQ-01~04 확정 ([P0 계획](docs/implementation/P0-tech-data.md), [종료 기록](docs/implementation/P0-closeout.md)) | [개발·검증 계획](docs/06-development-and-validation.md)의 P0 종료 조건 |
| P1 한 프레임 표시 | 진행 중: 골격·픽셀 계약 완료, native 표시·SC 색 변환 자동 시험 pass·최종 실제 UI 대기. 전체 codec/LUT/Enhanced 지원은 후속 | 같은 문서의 P1 종료 조건 |
| P2 검사 탐색 | 미착수 | 같은 문서의 P2 종료 조건 |
| P3 연구 도구 | 미착수 | 같은 문서의 P3 종료 조건 |
| P4 저장·내보내기 | 미착수 | 같은 문서의 P4 종료 조건 |
| P5 개인용 배포 | 미착수 | 같은 문서의 P5 및 릴리스 합격 조건 |

P0~P5의 상세 계약과 수치 기준은 이 표에 복사하지 않는다. 단계 계획은 작업 착수 시 [진행 기록 안내](docs/implementation/README.md)에 연결한다.

## 다음 AI가 할 일

1. [AGENTS.md](AGENTS.md), 이 문서, [진행 기록 안내](docs/implementation/README.md)를 읽는다. 필요한 제품 문서와 해당 스킬만 추가로 읽는다.
2. 현재 브랜치·최근 커밋·미커밋 변경을 확인한다. 이 문서의 기준보다 새 변경이 있으면 실제 파일과 diff를 먼저 대조한다. 다른 작성자의 변경을 되돌리거나 자신의 완료 결과로 보고하지 않는다.
3. 진행 중인 작업과 파일 작성권을 확인한 뒤, 자신의 task ID·AI/세션 식별자·목표·수정 범위·기준 commit을 실제 단계 계획에 등록한다. 중앙 진행 문서는 조정 담당자 한 명이 관리한다.
4. [native 컬러 기록](docs/implementation/P1-native-color.md)과 [최신 결과](docs/implementation/results/P1-native-color.json)를 현재 source/binary hash 기준으로 사용한다. 이전 DISPLAY 결과는 core/lib·native·Package/check와 binary가 후속 확장되기 전 snapshot이다. GUI를 사용할 수 있으면 최신 debug/release `check.sh --ui`·`--release --ui`, 실제 Command O/파일 선택 창→Ready, 사용자 대비·반전·확대/이동 후 `display-unrenderable-window.dcm` 실패→기존 상태 복구·재시도와 SC 컬러 controls를 확인한다. 최종 UI 근거를 회수하고 독립 리뷰 뒤 표시 묶음을 종료한다. GUI 대기가 독립적인 다음 구현을 막지는 않는다. 다음 최소 과업은 준비된 Palette16 LUT fixture의 producer와 자동 소비자 시험이며, US IOD·압축/frame 경계·전체 P1 지원 판정은 별도다. macOS27.0·원본 보존·수명/예산 계약을 유지한다.
5. 중단하거나 작업을 마칠 때 현재 상태, 변경 파일, 실제 실행한 검증과 미실행 이유, 미해결 사항, 다음 한두 작업을 기록한다. 커밋하지 않은 파일과 이어서 실행할 명령도 구분한다.

사용자 개인 DICOM 자료는 없다. `local-data/`의 공개 샘플을 쓰고, 합성 자료가 필요하면 기대값을 독립 계산한다. 실제 자료는 사용·재배포 조건과 비식별 상태를 확인한다.

### 환경과 작업 방식 메모 (2026-09-30 기준)

- 대상 Mac: Apple M5, 16 GiB. P0/골격은 macOS 27.0, 2026-10-01 픽셀 최종 검증은 **27.0.1(26A434)**. Xcode 대신 Command Line Tools·Swift 6.4, Rust 1.98.1(aarch64), 시스템 Python 3.9.6 사용. CODEC는 캐시의 uv Python 3.12.13·CMake 4.4.3 격리 환경을 사용한다. Intel 미지원, App Store·유료 개발자 계정 없음(사용자 결정).
- Xcode 없이 SwiftPM으로 AppKit·Metal 빌드와 **런타임 shader 컴파일** 확인. 오프라인 `metal` 컴파일러 없음 → P1 shader는 `makeLibrary(source:)` 경로.
- 실험 실행: `bash experiments/p0-ffi/run.sh` (전체 검사), `run.sh mem`, `run.sh real`. 빌드 산출물은 `~/Library/Caches/dicom-viewer/p0-ffi/`.
- P0-FFI 핵심 결론: UniFFI 0.32.2 + Rust 정적 라이브러리 + SwiftPM 채택 권고. **픽셀은 레코드 `Vec<u8>` 반환 대신 Rust 보유 프레임 → Swift 소유 버퍼로 1회 복사(`copy_into`)** 권고(16 MiB 이상에서 레코드 경로 footprint 누적). 무거운 호출은 async 또는 Task.detached, 취소는 명시적 토큰.
- P0-FFI-CONTRACT: `bash experiments/p0-ffi-contract/run.sh`. Rust 보유 불변 프레임 + UniFFI handle + 불투명 ticket의 타입 있는 C 복사 함수 + Swift 안전 래퍼. Mac에서 pass 11 / fail 0, 64 MiB 복사 p50 약 1.1 ms. 실험 deployment target 14.0은 제품 기준이 아니다.
- P0-DATA: `~/Library/Caches/dicom-viewer/p0-codec/venv/bin/python experiments/p0-data/prepare.py`. 합성 CT 32·DX 3·US 3을 `~/Library/Caches/dicom-viewer/p0-data/`에 생성한다.
- Claude(Cowork)는 Mac 터미널에 입력할 수 없다(클릭 전용 권한). Mac 실행이 필요하면 사용자에게 스크립트 한 줄을 요청하고, 실패 시 `experiments/p0-ffi-contract/results/failure-log.txt`(git 제외, 홈 경로 마스킹)를 읽는다.
- P0-CODEC: dicom-rs 0.10.0 baseline+charls+openjpeg-sys 채택(OQ-03). 이 조합은 284 pass / 33 fail / 5 not-run / 59 not-applicable. `bash experiments/p0-codec/run.sh all`은 6개 조합, 각 381개를 비교하며 알려진 실패·미검증 때문에 exit 1이다. 그레이 저장 값 정규화·컬러·프레임 경계 보완 전 지원 완료로 쓰지 않는다.
- 공개 저장소이므로 로컬 절대경로가 찍히는 빌드 로그는 커밋하지 않는다. CODEC 원시 로그·생성 DICOM·golden·target은 `~/Library/Caches/dicom-viewer/p0-codec/`에 있다.

## 확인된 검증과 한계

- 역할 TOML 4개와 스킬 6개 형식 검사 통과. 현재 구성의 파일 연결은 `python3 .agents/skills/dicom-orchestrate/scripts/validate_setup.py`로 재확인한다.
- 6개 프로젝트 스킬의 발견과 지침 전달 방식의 코어·앱·fixture·리뷰 역할 실행을 확인했다. 해당 시험은 문서 읽기와 사례 판단이며 제품 구현 시험이 아니다.
- 초기 세션은 커스텀 역할 선택 인자가 없어 지침 전달 방식을 썼다. 이번 세션은 도구의 `agent_type`으로 위 3개 역할을 호출했다. 다른 클라이언트의 자동 역할 호출과 실제 read-only 권한 격리는 별도 확인 대상이다.
- P0 전체 독립 검토(읽기 전용 reviewer 서브에이전트)는 차단 결함 없이 조건부 완료로 판정했다. 조건(C08 결과 재생성)은 충족했다.
- P0-ENV·P0-FFI·P0-CODEC·P0-DATA·P0-FFI-CONTRACT 실험은 실제 Mac에서 실행했다. CODEC 6개 release build, Rust 시험 3개, 참조 신뢰 경계 시험 8개 pass; 전체 픽셀 비교에는 fail/not-run이 남는다. CODEC 독립 검토는 전체 P0 종료 검토가 아니다. 실제 앱·GPU 표시·저장·정식 지원 시험은 아직 `not-run`이다.

## 미해결 사항과 재개 지점

- 최신 커밋의 push 여부를 `git status -sb`로 확인한다. 강제 push하지 않는다.
- P0-FFI 메모리: 레코드 경로의 대형 버퍼 footprint 누적 원인은 할당기 수준으로 추정만 되어 있다(Rust 누수는 배제). 제품에서는 `copy_into` 경로를 쓰면 영향이 없다.
- P0-DATA 부족 자료: tilt 없는 일반 CT 시리즈, DX, 긴 US cine. TCIA 등은 Cowork 네트워크 정책으로 막혀 있었으므로 필요하면 사용자가 직접 받는다.
- P0 종료 당시 not-run/open 전체 목록은 [P0 종료 기록](docs/implementation/P0-closeout.md)의 마지막 절에 있다. PIXEL-1은 좁은 native decode–handle 결합, payload 수명·예산, 세션당 준비 1개와 프레임 제한을 확인했다. 전체 codec, 요청·취소(T-12), GPU 완료, 정식 T-11·T-13과 engine/parser/RSS 한도, OQ-06 저장 장치·전원 모드는 남는다.
- CODEC 제품 전제: 부호·유효 비트 저장 값 정규화, planar·색 변환, 손상 BOT/EOT·frame count 검증 및 빈 BOT의 다중 fragment 지원. Enhanced FG Modality oracle은 not-run, parser/codec 전체 할당 한도도 미검증이다.
- `.agents/skills/dicom-orchestrate/scripts/validate_setup.py`는 PyYAML·tomli가 없는 환경에서 실행되지 않는다(스크립트 문제 아님).
- P0에서 [README의 OQ 목록](README.md)과 [개발·검증 계획](docs/06-development-and-validation.md)을 확인한다. 아직 확정하지 않은 기술을 확정된 구현으로 재사용하지 않는다.
- 새 AI의 출발점: 이 문서·native 컬러 기록/최신 JSON → 실제 Git/미커밋 변경 대조 → 가능할 때 최종 사용자 UI 회귀. UI 대기와 독립 과업을 분리한다. 묶음3·컬러준비·COLOR-1은 사용자 요청으로 후속 로컬 커밋에 포함했다. 골격/픽셀 commit `c68c920`과 구분하며 최신 식별자는 `git log -1`로 확인한다.

현재 작업: [native SC 컬러](docs/implementation/P1-native-color.md) 자동 구현·검증·독립 근거 대조 완료, [native 표시](docs/implementation/P1-native-display.md) 실제 UI 대기. 코드 작성권 root·로컬 커밋 포함·push 없음. 실제 UI not-run과 다음 Palette16 과업은 유지한다.

## P1 골격에서 확인한 내용

- `bash scripts/check.sh --ui`: Rust fmt/clippy·locked debug build, Swift의 실제 Rust 초기 호출, 기본 창·메뉴·비활성 열기·마지막 창 닫기 종료 pass.
- `bash scripts/build.sh release`와 release 앱의 bootstrap/UI smoke pass. 두 실행파일은 arm64·minos 27.0이며 Rust 정적 링크다. CUA로 개발용 앱의 실제 기본 창을 시각 확인했다.
- 소스·binary 해시와 기동 결과: [P1-foundation.json](docs/implementation/results/P1-foundation.json). 독립 reviewer가 필수 수정 결함 없이 소스·생성기·소비자·로그/해시를 대조했다.
- 생성 바인딩·header·라이브러리는 Git 제외. 개발용 앱은 `~/Library/Caches/dicom-viewer/p1/app-debug/DICOM Viewer.app`; 임시 식별자이며 정식 설치·서명은 미검증이다.
- 골격 종료 당시 실제 DICOM·픽셀·Metal/GPU·정식 T-11~13/T-20은 not-run이었다. 후속 픽셀 검증은 아래에 따로 기록한다.

## P1 픽셀 계약에서 확인한 내용

- `bash scripts/check.sh` 및 `--release`: 각각 Rust core 16+FFI 6, Swift 실제 DICOM 계약 18, bootstrap·원본 hash 보존 pass. 별도 debug/release UI smoke도 창·메뉴·마지막 창 닫기 종료 pass.
- Gray LE/BE/implicit의 signed 유효 비트·rescale·padding mask와 RGB SC의 RGBA bytes를 전 픽셀 비교했다. 보유 handle은 evict/close 후에도 Rust 예산에 남고, 마지막 참조 해제 시 반환한다. Swift 별도 복사 예산·별칭·동시 복사·거부 후 재수용도 확인했다.
- [결과 JSON](docs/implementation/results/P1-pixel-contract.json): source 28개·생성물 3개·fixture 10개 및 debug/release binary hash. 개발용 bundle은 새 inode 교체·ad-hoc 서명·strict verify를 수행하며 arm64/minos27.0·static Rust 링크다.
- 독립 reviewer 필수 수정 결함 0. 최종 source/fixture/binary/log hash와 signed bundle·linkage를 대조하고 pydicom으로 합성 4개의 stored 값도 직접 확인했다. 재빌드·앱 실행·파일 수정은 하지 않았다.
- 앱 영상 표시·VOI/극성/종횡비·source/generation·GPU 수명, 전체 codec/parser/engine 한도·RSS/성능·P5 설치는 미검증이다. 단계 전체 합격으로 확대하지 않는다.

작업별 변경·검증·인수인계 이력은 [work-log.md](docs/implementation/work-log.md)에 있다.

## P1 native 표시의 종료 시점 검증 (후속 COLOR-1 전)

- 최종 소스 debug/release `bash scripts/check.sh` / `--release`: fmt/clippy·Rust core28+FFI7·PIXEL18·Metal26·원본 hash 보존 pass. 작은 CPU reference와 독립 literal 기대값을 실제 GPU 전 픽셀과 비교했고 VOI 수치 경계·mask 보간·비율/좌표·generation/state 복구 정책·GPU 완료 수명·과대 texture 거부를 확인했다.
- 마지막 재표시 수정 전 startup UI smoke는 두 profile pass였으나 실제 NSOpenPanel에서 무한 Loading을 발견했다. 후보의 실제 presentation까지 연속 재표시하고 Ready/Fail/새 요청/닫기 때 정지하도록 수정했다. 마지막 버전의 `--ui`와 실제 파일 선택 창·이전 사용자 설정 복구는 **not-run (Mac 잠금, 사용자에게 해제 요청)**이다.
- 독립 reviewer는 소스상 발견한 필수 결함의 수정과 CLI/fixture 근거를 확인했지만 최종 실제 UI 회귀 전에는 DISPLAY-1 완료를 보류한다. [결과 스냅샷](docs/implementation/results/P1-native-display.json)은 이전 UI 기록과 현재 자동 검증을 구분한다. P0는 변경하지 않았다.


## P1 native SC 컬러의 최신 검증

- `bash scripts/check.sh`·`--release` 각각 Rust core38+FFI7, PIXEL18, DISPLAY26, COLOR29와 bootstrap·원본hash pass. RGB/YBR literal7종, 예상 거부19종, 2배 선형 보간·W/L/invert 무변화·확장 RGBA 예산·close 이후 GPU 마지막 owner 해제를 확인했다.
- [최신 JSON](docs/implementation/results/P1-native-color.json)은 source39/generated3/fixture50/binary8/log2/report8을 기록한다. 공개 선언/생성물3개와 준비source2·manifest는 그대로다. 기존 DISPLAY35개 중4개만 이번에 확장했다. P0 변경 없음.
- reviewer가 최종 소스와 독립 YBR 수치(최대차1), 모든 저장 hash/로그/보고서/binary를 확인했고 필수 결함0으로 좁은 COLOR-1 자동 범위 완료를 판정했다. 양쪽 bundle strict/deep ad-hoc 서명·실행파일8개 arm64/minos27/static Rust main 확인. 실제 UI는 not-run이며 전체 앱 지원으로 확대하지 않는다.
