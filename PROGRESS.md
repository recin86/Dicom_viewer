# DICOM Viewer 진행 상황과 인수인계

최종 갱신: 2026-09-30 (Asia/Seoul, Claude(Cowork) P0 종료). 이 문서는 현재 상태의 요약이다. 코드·Git 이력·실제 시험 결과와 대조해서 읽는다. 갱신하지 않은 문서나 이전 AI의 대화만으로 완료를 판단하지 않는다.

## 현재 위치

**P0 완료 (2026-09-30). 다음은 P1 계획.** 제품 코드(`crates/`, `macos/`)는 아직 없고 `experiments/`의 P0 실험 코드만 있다. P0 완료는 제품 지원이나 릴리스 합격을 뜻하지 않으며, CODEC 실패와 not-run 항목은 그대로 P1 이후 과제다([P0 종료 기록](docs/implementation/P0-closeout.md)).

| 항목 | 현재 상태 | 근거 |
| --- | --- | --- |
| 제품 설계 | 문서 0.2. OQ-01~04 확정, ADR 0002 채택(P0 종료). 나머지 ADR은 제안 | [README](README.md), [ADR](docs/adr/README.md) |
| 에이전트 구성 | 공통 지침, 역할 4개, 전용 스킬 6개 작성·검증 | [AGENTS.md](AGENTS.md), [운영 안내](docs/07-agent-development.md) |
| 역할 실행 | 초기 지침 전달 방식 4개 역할 확인; 이번 Codex 도구의 agent_type으로 dicom_core·dicom_fixtures·dicom_reviewer 실제 호출 | [작업 이력](docs/implementation/work-log.md) |
| 로컬 Git | `~/Documents/Dicom_viewer`, `main`; P0-CODEC과 P0-CLOSE 변경을 각각 커밋(기준 `ea7e2b3` 이후 2 commit). push는 사용자가 Mac에서 수행 | `git log --oneline`, `git status` |
| 원격 저장소 | `origin` = https://github.com/recin86/Dicom_viewer.git (공개). 로컬 추적 origin/main=`49b444e`, main은 1 commit 앞섬. 이번 작업에서 commit/push·원격 재조회 없음 | `git status -sb`, `git rev-parse origin/main` |
| 구현과 자료 | 제품 코드 없음. 실험: `p0-env`, `p0-ffi`, `p0-codec`, `p0-data`, `p0-ffi-contract`. 공개 331개는 ignored local-data; CODEC 합성 50개·DATA 합성 38개·golden·binary는 저장소 밖 캐시. 결과 JSON에는 fixture ID·영상 형식·공개 출처·해시만 | [CODEC](experiments/p0-codec/README.md), [DATA](experiments/p0-data/README.md), [FFI 계약](experiments/p0-ffi-contract/README.md) |
| 현재 작업자·작성권 | 없음. Claude(Cowork)가 P0-CLOSE-20260930을 Codex에서 인수해 종료. 실행 중 작업 없음 | [P0 종료 기록](docs/implementation/P0-closeout.md) |

## 단계별 진행

| 단계 | 상태 | 다음 완료 기준의 근거 |
| --- | --- | --- |
| 운영 준비 | 완료 | 설계·역할·스킬, 로컬 Git, 진행 문서와 인수인계 규칙 |
| P0 기술·자료 확인 | **완료 (2026-09-30)**: ENV·DATA·CODEC·FFI·FFI 계약·DIST, 전체 독립 검토, OQ-01~04 확정 ([P0 계획](docs/implementation/P0-tech-data.md), [종료 기록](docs/implementation/P0-closeout.md)) | [개발·검증 계획](docs/06-development-and-validation.md)의 P0 종료 조건 |
| P1 한 프레임 표시 | 미착수 (다음: 계획 작성) | 같은 문서의 P1 종료 조건 |
| P2 검사 탐색 | 미착수 | 같은 문서의 P2 종료 조건 |
| P3 연구 도구 | 미착수 | 같은 문서의 P3 종료 조건 |
| P4 저장·내보내기 | 미착수 | 같은 문서의 P4 종료 조건 |
| P5 개인용 배포 | 미착수 | 같은 문서의 P5 및 릴리스 합격 조건 |

P0~P5의 상세 계약과 수치 기준은 이 표에 복사하지 않는다. 단계 계획은 작업 착수 시 [진행 기록 안내](docs/implementation/README.md)에 연결한다.

## 다음 AI가 할 일

1. [AGENTS.md](AGENTS.md), 이 문서, [진행 기록 안내](docs/implementation/README.md)를 읽는다. 필요한 제품 문서와 해당 스킬만 추가로 읽는다.
2. 현재 브랜치·최근 커밋·미커밋 변경을 확인한다. 이 문서의 기준보다 새 변경이 있으면 실제 파일과 diff를 먼저 대조한다. 다른 작성자의 변경을 되돌리거나 자신의 완료 결과로 보고하지 않는다.
3. 진행 중인 작업과 파일 작성권을 확인한 뒤, 자신의 task ID·AI/세션 식별자·목표·수정 범위·기준 commit을 실제 단계 계획에 등록한다. 중앙 진행 문서는 조정 담당자 한 명이 관리한다.
4. 다음은 **P1 계획 작성**이다. [개발·검증 계획](docs/06-development-and-validation.md)의 P1 종료 조건을 단계 계획(`docs/implementation/P1-<주제>.md`)으로 나눈다. 첫 계약 과제: 보유 handle의 메모리 예산 규칙(검토 F3), FramePayload handle 모델의 API 문서화(F4 후속), C 복사 모듈을 Swift 래퍼의 비공개 의존성으로 격리(F5). CODEC 제한(저장 값 정규화·컬러·빈 BOT 다중 fragment·손상 경계·JPEG Extended)은 P1 adapter 과제로 배정한다. 제품 deployment target은 macOS 27.0.
5. 중단하거나 작업을 마칠 때 현재 상태, 변경 파일, 실제 실행한 검증과 미실행 이유, 미해결 사항, 다음 한두 작업을 기록한다. 커밋하지 않은 파일과 이어서 실행할 명령도 구분한다.

사용자 개인 DICOM 자료는 없다. `local-data/`의 공개 샘플을 쓰고, 합성 자료가 필요하면 기대값을 독립 계산한다. 실제 자료는 사용·재배포 조건과 비식별 상태를 확인한다.

### 환경과 작업 방식 메모 (2026-09-30 기준)

- 대상 Mac: Apple M5, 16 GiB, macOS 27.0, **Xcode 없음**(Command Line Tools 27.0, Swift 6.4), Rust 1.98.1(aarch64), 시스템 Python 3.9.6. CODEC는 캐시의 uv Python 3.12.13·CMake 4.4.3 격리 환경을 사용한다. Intel 미지원, App Store·유료 개발자 계정 없음(사용자 결정).
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
- P0 종료 후에도 남는 not-run/open 전체 목록은 [P0 종료 기록](docs/implementation/P0-closeout.md)의 마지막 절에 있다. 주요 항목: 실제 decode–handle 결합, 요청·취소(T-12), GPU 완료 순서, T-11·T-13, 최대 동시 디코딩 수와 단일 프레임 한도, OQ-06 저장 장치·전원 모드.
- CODEC 제품 전제: 부호·유효 비트 저장 값 정규화, planar·색 변환, 손상 BOT/EOT·frame count 검증 및 빈 BOT의 다중 fragment 지원. Enhanced FG Modality oracle은 not-run, parser/codec 전체 할당 한도도 미검증이다.
- `.agents/skills/dicom-orchestrate/scripts/validate_setup.py`는 PyYAML·tomli가 없는 환경에서 실행되지 않는다(스크립트 문제 아님).
- P0에서 [README의 OQ 목록](README.md)과 [개발·검증 계획](docs/06-development-and-validation.md)을 확인한다. 아직 확정하지 않은 기술을 확정된 구현으로 재사용하지 않는다.
- 새 AI의 출발점: 이 문서와 P0 종료 기록 확인 → 커밋 범위를 사용자와 정리 → P1 계획 작성.

작업별 변경·검증·인수인계 이력은 [work-log.md](docs/implementation/work-log.md)에 있다.
