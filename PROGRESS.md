# DICOM Viewer 진행 상황과 인수인계

최종 갱신: 2026-09-30 17시경 (Asia/Seoul, Claude Cowork 세션 종료 시점). 이 문서는 현재 상태의 요약이다. 코드·Git 이력·실제 시험 결과와 대조해서 읽는다. 갱신하지 않은 문서나 이전 AI의 대화만으로 완료를 판단하지 않는다.

## 현재 위치

**P0 진행 중. P0-ENV·P0-FFI 완료, P0-DATA 1차 수집 완료. 다음은 P0-CODEC.** 제품 코드(`crates/`, `macos/`)는 아직 없고 `experiments/`의 P0 실험 코드만 있다.

| 항목 | 현재 상태 | 근거 |
| --- | --- | --- |
| 제품 설계 | 문서 0.2 작성·검토 완료, 기술 제안은 검증 전 | [README](README.md), [ADR](docs/adr/README.md) |
| 에이전트 구성 | 공통 지침, 역할 4개, 전용 스킬 6개 작성·검증 | [AGENTS.md](AGENTS.md), [운영 안내](docs/07-agent-development.md) |
| 역할 실행 | 지침 전달 방식으로 4개 역할의 스킬 읽기·경계 적용 확인 | [작업 이력](docs/implementation/work-log.md) |
| 로컬 Git | 프로젝트 위치 `~/Documents/Dicom_viewer` (2026-09-30 OneDrive에서 이동). `main`: `e4a9544` → `b02c49b` → `49b444e` 이후 인수인계 커밋 | `git log --oneline`, `git status` |
| 원격 저장소 | `origin` = https://github.com/recin86/Dicom_viewer.git (공개). `b02c49b`까지 push 확인. 이후 커밋은 사용자가 Mac에서 push (Cowork VM에는 GitHub 인증 없음) | `git status -sb`, `git ls-remote origin` |
| 구현과 자료 | 제품 코드 없음. 실험: `experiments/p0-env/`, `experiments/p0-ffi/`. 시험 자료: `local-data/`(Git 제외, 공개 샘플 331개: pydicom MIT, dcm_qa_ct BSD-2; 목록 `local-data/20260930_DicomViewer_sample-inventory_ver1.1_KMJ.csv`) | [local-data/README.md](local-data/README.md) (로컬 전용) |
| 현재 작업자·작성권 | 없음. Claude(Cowork) 조정 종료, 사용자가 이후 작업을 Codex로 진행 예정. 실행 중인 작업·미커밋 변경 없음 | [P0 계획](docs/implementation/P0-tech-data.md)의 배정 표 |

## 단계별 진행

| 단계 | 상태 | 다음 완료 기준의 근거 |
| --- | --- | --- |
| 운영 준비 | 완료 | 설계·역할·스킬, 로컬 Git, 진행 문서와 인수인계 규칙 |
| P0 기술·자료 확인 | 진행 중: ENV 완료, FFI 완료(픽셀 경로 권고 포함), DATA 1차 수집, CODEC·DIST 기록·REVIEW 남음 ([P0 계획](docs/implementation/P0-tech-data.md)) | [개발·검증 계획](docs/06-development-and-validation.md)의 P0 종료 조건 |
| P1 한 프레임 표시 | 미착수 | 같은 문서의 P1 종료 조건 |
| P2 검사 탐색 | 미착수 | 같은 문서의 P2 종료 조건 |
| P3 연구 도구 | 미착수 | 같은 문서의 P3 종료 조건 |
| P4 저장·내보내기 | 미착수 | 같은 문서의 P4 종료 조건 |
| P5 개인용 배포 | 미착수 | 같은 문서의 P5 및 릴리스 합격 조건 |

P0~P5의 상세 계약과 수치 기준은 이 표에 복사하지 않는다. 단계 계획은 작업 착수 시 [진행 기록 안내](docs/implementation/README.md)에 연결한다.

## 다음 AI가 할 일

1. [AGENTS.md](AGENTS.md), 이 문서, [진행 기록 안내](docs/implementation/README.md)를 읽는다. 필요한 제품 문서와 해당 스킬만 추가로 읽는다.
2. 현재 브랜치·최근 커밋·미커밋 변경을 확인한다. 이 문서의 기준보다 새 변경이 있으면 실제 파일과 diff를 먼저 대조한다. 다른 작성자의 변경을 되돌리거나 자신의 완료 결과로 보고하지 않는다.
3. 진행 중인 작업과 파일 작성권을 확인한 뒤, 자신의 task ID·AI/세션 식별자·목표·수정 범위·기준 commit을 실제 단계 계획에 등록한다. 중앙 진행 문서는 조정 담당자 한 명이 관리한다.
4. 다음 제품 작업은 **P0-CODEC**이다. [P0 계획](docs/implementation/P0-tech-data.md)의 P0-CODEC 절을 따른다: dicom-rs 0.10.x(`dicom-object`, `dicom-pixeldata`, `dicom-transfer-syntax-registry`) 버전·feature 고정, `local-data/`의 Transfer Syntax별 디코딩 결과를 독립 참조(pydicom 등)와 비교, 음수 intercept·비단위 slope 자료로 rescale 중복 여부 확인, 압축 multi-frame 프레임 경계. 그 뒤 P0-DIST 기록(방향은 확정됨), P0-REVIEW, OQ 확정과 ADR 0002·docs/04 반영.
5. 중단하거나 작업을 마칠 때 현재 상태, 변경 파일, 실제 실행한 검증과 미실행 이유, 미해결 사항, 다음 한두 작업을 기록한다. 커밋하지 않은 파일과 이어서 실행할 명령도 구분한다.

사용자 개인 DICOM 자료는 없다. `local-data/`의 공개 샘플을 쓰고, 합성 자료가 필요하면 기대값을 독립 계산한다. 실제 자료는 사용·재배포 조건과 비식별 상태를 확인한다.

### 환경과 작업 방식 메모 (2026-09-30 기준)

- 대상 Mac: Apple M5, 16 GiB, macOS 27.0, **Xcode 없음**(Command Line Tools 27.0, Swift 6.4), Rust stable(aarch64), Homebrew, cmake 없음, 시스템 python3 3.9. Intel 미지원, App Store·유료 개발자 계정 없음(사용자 결정).
- Xcode 없이 SwiftPM으로 AppKit·Metal 빌드와 **런타임 shader 컴파일** 확인. 오프라인 `metal` 컴파일러 없음 → P1 shader는 `makeLibrary(source:)` 경로.
- 실험 실행: `bash experiments/p0-ffi/run.sh` (전체 검사), `run.sh mem`, `run.sh real`. 빌드 산출물은 `~/Library/Caches/dicom-viewer/p0-ffi/`.
- P0-FFI 핵심 결론: UniFFI 0.32.2 + Rust 정적 라이브러리 + SwiftPM 채택 권고. **픽셀은 레코드 `Vec<u8>` 반환 대신 Rust 보유 프레임 → Swift 소유 버퍼로 1회 복사(`copy_into`)** 권고(16 MiB 이상에서 레코드 경로 footprint 누적). 무거운 호출은 async 또는 Task.detached, 취소는 명시적 토큰.
- 공개 저장소이므로 로컬 절대경로가 찍히는 빌드 로그는 커밋하지 않는다(`experiments/p0-ffi/.gitignore`).

## 확인된 검증과 한계

- 역할 TOML 4개와 스킬 6개 형식 검사 통과. 현재 구성의 파일 연결은 `python3 .agents/skills/dicom-orchestrate/scripts/validate_setup.py`로 재확인한다.
- 6개 프로젝트 스킬의 발견과 지침 전달 방식의 코어·앱·fixture·리뷰 역할 실행을 확인했다. 해당 시험은 문서 읽기와 사례 판단이며 제품 구현 시험이 아니다.
- 현재 호출 도구에는 커스텀 역할 선택 인자가 없다. [AGENTS.md](AGENTS.md)의 대체 위임 방식을 사용한다. 다른 클라이언트의 자동 역할 호출과 실제 read-only 권한 격리는 별도 확인 대상이다.
- P0-ENV·P0-FFI 실험은 사용자 Mac에서 실행해 결과를 `experiments/*/`와 P0 계획 실행 증거 절에 기록했다. 실제 앱 빌드, DICOM 디코딩, GPU 표시, 저장 시험은 아직 `not-run`이다. P0 실험 결과를 제품 지원 완료로 표현하지 않는다.

## 미해결 사항과 재개 지점

- 최신 커밋의 push 여부를 `git status -sb`로 확인한다. 강제 push하지 않는다.
- P0-FFI 메모리: 레코드 경로의 대형 버퍼 footprint 누적 원인은 할당기 수준으로 추정만 되어 있다(Rust 누수는 배제). 제품에서는 `copy_into` 경로를 쓰면 영향이 없다.
- P0-DATA 부족 자료: tilt 없는 일반 CT 시리즈, DX, 긴 US cine. TCIA 등은 Cowork 네트워크 정책으로 막혀 있었으므로 필요하면 사용자가 직접 받는다.
- `.agents/skills/dicom-orchestrate/scripts/validate_setup.py`는 PyYAML·tomli가 없는 환경에서 실행되지 않는다(스크립트 문제 아님).
- P0에서 [README의 OQ 목록](README.md)과 [개발·검증 계획](docs/06-development-and-validation.md)을 확인한다. 아직 확정하지 않은 기술을 확정된 구현으로 재사용하지 않는다.
- 새 AI의 출발점: 이 문서와 P0 계획 확인 → P0-CODEC 등록·실행 → P0-REVIEW → OQ-02·03·04 확정 → P1 계획.

작업별 변경·검증·인수인계 이력은 [work-log.md](docs/implementation/work-log.md)에 있다.
