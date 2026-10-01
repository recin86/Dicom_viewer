# macOS DICOM Viewer 개발 문서

개인 연구용 macOS 로컬 DICOM 뷰어를 개발하기 위한 문서 모음이다. CT, MR, X-ray, US를 대상으로 Rust와 dicom-rs로 영상 코어를 만들고 Swift로 macOS 앱을 구성한다. 특정 장비나 한 대의 Mac에만 맞춘 설계를 피하고, 지원 범위를 검증하면서 확장하는 것을 목표로 한다.

제품 설계 문서 버전은 0.2이며 구현 상태는 2026-10-01에 갱신했다. **P0·P1 골격·픽셀 계약 완료, native 표시와 SC 컬러 변환의 자동 검증 완료, 실제 사용자 UI 회귀 대기**다. `experiments/`는 기술 실험, `crates/`와 `macos/`는 제품 코드다. 제한된 native 단일 프레임→Rust 표시 설명→Swift 소유 버퍼→Metal을 연결했다. 자동 검증과 수동 사용자 경로의 마지막 검증 상태는 [표시 기록](docs/implementation/P1-native-display.md)을 따른다. SC RGB planar·YBR_FULL·YBR_FULL_422 변환과 debug/release FFI·Metal 검증은 [컬러 기록](docs/implementation/P1-native-color.md)에 둔다. 전체 P1·앱 성능·정식 DICOM 지원 판정은 후속이다.

**작업을 이어받는 AI는 [AGENTS.md](AGENTS.md)와 [현재 진행 상황](PROGRESS.md)을 먼저 읽는다.** 단계별 배정·검증·인수인계는 [진행 기록 안내](docs/implementation/README.md)와 [작업 이력](docs/implementation/work-log.md)에 남긴다.

## 문서 안내

| 문서 | 책임과 내용 |
| --- | --- |
| [제품 요구사항](docs/01-product-requirements.md) | 사용자 목적, 기능 요구사항, 버전별 범위와 미결정 사항 |
| [시스템 아키텍처](docs/02-system-architecture.md) | Rust와 Swift의 경계, 렌더링, 비동기 처리, 캐시와 저장 |
| [DICOM 지원 명세](docs/03-dicom-support.md) | 입력 형식, 프레임 해석, 표시와 측정 규칙, 지원 판정 |
| [코어 API와 데이터 모델](docs/04-core-api-and-data-model.md) | 내부 모델, FFI 계약, 오류, 수명, 취소와 영속 데이터 |
| [화면과 조작 명세](docs/05-ui-and-interaction.md) | 화면, 탐색, 도구, 재생, 저장과 오류 상황의 사용자 경험 |
| [개발과 검증 계획](docs/06-development-and-validation.md) | 구현 단계, 테스트 자료, 정확성, 성능, 빌드와 배포 |
| [설계 결정 기록](docs/adr/README.md) | 기술 선택의 배경, 대안과 재검토 조건 |
| [에이전트 개발 운영](docs/07-agent-development.md) | 메인·서브에이전트 분담, 프로젝트 스킬, 작성권과 검증 방법 |

처음 읽을 때는 제품 요구사항 → DICOM 지원 명세 → 아키텍처 → API와 데이터 모델 → 화면과 조작 → 개발과 검증 순서를 권장한다. 기능을 구현할 때는 해당 요구사항과 연결된 검증 항목을 함께 읽는다.

## 확정 사항과 제안의 구분

**사용자와의 대화에서 확정된 사항**은 macOS 앱, 개인 연구용 로컬 사용, CT/MR/X-ray/US, Rust와 dicom-rs 코어, Swift 앱, 범용성을 고려한 설계, 구현에 앞선 문서 작성이다.

**P0에서 채택한 사항**은 UniFFI 0.32.2·Rust 정적 라이브러리·SwiftPM 연결과 타입 있는 픽셀 복사 방향이다. P1은 AppKit·MTKView와 Metal 표시를 연결했다. SwiftUI 일반 화면, 전체 프레임 모델·SQLite·성능 목표·영상/저장 API는 후속 제안이다. 좁은 단일 프레임 검증을 정식 전체 지원으로 확대하지 않는다.

문서 안의 규범형 문장은 해당 작업안을 채택할 경우 지켜야 할 구현 계약을 뜻한다. 목표 버전은 일정 약속이 아니다.

## 변경 원칙

- 기능의 필요성과 우선순위는 제품 요구사항이 관리한다.
- DICOM 의미와 지원 범위는 DICOM 지원 명세가 관리한다.
- 모듈 책임과 실행 흐름은 시스템 아키텍처가 관리한다.
- 필드, 단위, API, 메모리 소유권은 API와 데이터 모델이 관리한다.
- 입력 동작과 사용자 표시 문구는 화면과 조작 명세가 관리한다.
- 합격 기준과 시험 결과 기록 방법은 개발과 검증 계획이 관리한다.
- 중요한 선택은 ADR에 기록하고, 관련 문서 링크를 함께 갱신한다.

충돌하는 내용이 발견되면 해당 주제의 담당 문서를 먼저 수정한 뒤 참조 문서를 맞춘다. 동일한 정의를 여러 문서에 독립적으로 유지하지 않는다. 요구사항 ID와 시험 ID는 변경 후에도 추적 가능하게 유지한다.

## 개발 전에 결정할 항목

| ID | 항목 | 현재 작업안 | 결정 시점 |
| --- | --- | --- | --- |
| OQ-01 | 최소 macOS와 CPU 지원 | **확정(P0 종료 2026-09-30): Apple Silicon(arm64)만, 최소 macOS 27.0.** CPU와 최소 OS 모두 사용자 확인(2026-09-30). 시험 가능한 기기가 macOS 27.0 한 대뿐이라 더 낮은 OS는 지원하지 않는다. 하위 OS 지원은 실제 기기 시험 후 새 결정으로 연다 | 확정 |
| OQ-02 | Rust와 Swift 연결 | **확정(P0 종료 2026-09-30): UniFFI 0.32.2 + Rust 정적 라이브러리 + SwiftPM(Command Line Tools).** 픽셀·mask는 Rust 보유 불변 프레임에서 Swift 소유 버퍼로 1회 복사하는 타입 있는 C 함수(불투명 ticket)와 Swift 안전 래퍼로 전달. 근거 [ADR 0002](docs/adr/0002-uniffi-and-pixel-buffers.md), [P0-FFI-CONTRACT](experiments/p0-ffi-contract/README.md) | 확정 |
| OQ-03 | 추가 압축 코덱 | **확정(P0 종료 2026-09-30): dicom-rs 0.10.0 baseline(native·deflate·jpeg·rle) + charls(JPEG-LS) + openjpeg-sys(JPEG 2000, C OpenJPEG)를 v0.1 대상으로 포함.** 저장 값 정규화·컬러·빈 BOT 다중 fragment·손상 경계·JPEG Extended·일부 공개 Modality 불일치 등 [제한 표](experiments/p0-codec/README.md#픽셀-변환-호출-규칙과-제한)의 실패와 not-run 5건은 P1 adapter에서 해소하거나 capability로 차단한 뒤 지원 판정. HTJ2K·JPEG XL·video 제외 유지. 근거 [P0-CODEC](experiments/p0-codec/README.md) | 확정 |
| OQ-04 | Enhanced CT/MR 우선순위 | **확정(P0 종료 2026-09-30): v0.2 후보 유지.** 사용자 실제 자료가 없고 공개 331개 중 Enhanced CT 1·MR 5개(파일 수는 임상 빈도가 아님)라 v0.1 필수로 올릴 근거가 없다. v0.1은 Enhanced를 식별해 제한 상태로 보이고 일반 스택으로 오인하지 않는다. 사용자가 Enhanced 자료를 주로 쓰게 되면 범위 변경으로 다시 논의 | 확정 |
| OQ-05 | 배포 방식과 앱 파일 권한 | **App Store 등록 안 함, 유료 Apple 개발자 계정 없음 (사용자 확정 2026-09-30).** 개인용 직접 빌드·설치, ad-hoc 서명, App Sandbox 미사용 작업안 | 방향 확정, P5에서 검증 |
| OQ-06 | 성능 기준 장비와 자료 | **기준 장비 초안: Apple M5 MacBook Air, 16 GiB, macOS 27.0, 외부 4K(UI 1920×1080, 2×) (P0-ENV 2026-09-30).** 샘플 특성은 P0-DATA에서 기록(DATA 준비 [preparation.json](experiments/p0-data/results/preparation.json)). 저장 장치와 전원 모드는 아직 기록하지 않았으므로 P2 성능 측정 전에 보완 | P0에서 지정, P2에서 목표 검토 |
| OQ-07 | 연구 프로젝트 저장 | 원본 참조와 별도 프로젝트 문서, 앱 인덱스는 SQLite | P3 시작 전 |
| OQ-08 | 첫 버전의 측정 범위 | CT/MR과 보정 가능한 X-ray의 기본 측정, US 물리 측정은 후속 후보 | P3 시작 전 |
| OQ-09 | 앱 이름과 식별자 | DICOM Viewer는 작업용 이름 | P5 시작 전 |

이 항목들은 개발 단계의 확인점이며, 매 작업마다 사용자 확인을 요구하는 절차가 아니다. 기술 실험으로 결정할 수 있는 사항은 결과와 이유를 기록해서 해결한다. 사용자 목적이나 지원 범위를 바꾸는 선택은 별도로 논의한다.

## 자료와 상태 기록

기술 참고 자료는 각 문서의 관련 설명과 참고 자료 항목에 연결했다. 라이브러리 문서의 지원 표는 앱의 검증 결과가 아니다. 개발을 시작할 때 실제 의존성 버전과 기능 옵션을 고정하고 시험 자료 및 결과를 연결한다.

P1 계획과 골격 이력은 [P1 한 프레임 표시](docs/implementation/P1-single-frame.md), 불변 handle·복사·예산은 [픽셀 계약](docs/implementation/P1-pixel-contract.md), 파일 입력·VOI·GPU·generation은 [native 표시](docs/implementation/P1-native-display.md), SC 색 변환의 최신 소스·자동 검증은 [native 컬러](docs/implementation/P1-native-color.md)에 기록한다. 전체 FramePayload·프레임 탐색·영속 요청 API는 후속이다.

## 제품 골격 빌드와 실행

Apple Silicon·macOS 27.0 이상, Rust 1.98.1, Swift 6.4 Command Line Tools, CMake와 Python 3가 필요하다. Xcode는 필요하지 않다. CMake가 PATH에 없으면 기존 P0 codec의 격리 환경(`~/Library/Caches/dicom-viewer/p0-codec/venv/bin`)을 사용한다. 다른 Mac에서는 CMake를 별도로 준비해야 한다.

프로젝트 루트에서 실행한다.

```sh
bash scripts/build.sh             # debug Rust·UniFFI 생성·Swift 빌드
bash scripts/build.sh release     # release 빌드
bash scripts/check.sh             # Rust·Swift 픽셀/SC 컬러 계약·Metal 기준 비교·좌표/수명
bash scripts/check.sh --release   # 같은 계약을 최적화 빌드에서 검증
bash scripts/check.sh --ui        # 잠금 해제된 GUI: 창·실제 drawable 표시·종료
bash scripts/run.sh               # 최신 소스를 빌드하고 기본 창 실행
```

열기 버튼 또는 Command O로 한 파일을 선택한다. 구현 대상은 제한된 native CT/MR/회색조 SC와 unsigned8 RGB·YBR_FULL·even-width YBR_FULL_422 SC다. 회색조는 대비·반전, 공통 영상은 맞춤·확대·이동을 제공한다. 컬러는 Rust에서 RGBA로 한 번 변환하고 회색조 대비·반전은 적용하지 않는다. 압축·Enhanced·다중 프레임·LUT는 현재 명시 거부한다. 원본 DICOM은 수정하지 않는다. 자동 입력은 `bash scripts/run.sh --open PATH`이며 실제 사용자 경로의 최신 검증 상태는 위 표시 기록을 확인한다.

산출물과 합성 DICOM은 기본적으로 `~/Library/Caches/dicom-viewer/p1/`에 두며 `DICOM_VIEWER_CACHE`로 별도 캐시를 지정할 수 있다. 생성된 Swift/header/module map과 링크용 정적 라이브러리만 ignored `macos/` 경로에 복사한다. 생성 바인딩은 손으로 수정하지 않는다. 개발용 앱은 캐시의 `app-debug/DICOM Viewer.app` 또는 `app-release/DICOM Viewer.app`이며 직접 열어 기본 창을 볼 수 있다. 빌드 중 로컬 실행용 ad-hoc 서명과 검증을 수행한다. 임시 식별자는 `local.dicomviewer.development`다(OQ-09 최종 이름·식별자 미결정). 설치·배포 서명·Gatekeeper·다른 Mac 배포는 P5 과제다.

## 문서 검토 결과 · 0.2

전체 12개 문서의 역할 분리와 기본 기술 방향을 유지하면서, 구현 결과가 달라질 수 있는 누락과 모호한 계약을 보완했다. 아래 변경은 설계 검토 결과이며 실제 앱의 검증 완료를 뜻하지 않는다.

| 검토 항목 | 발견 내용과 수정 | 반영 문서 |
| --- | --- | --- |
| 코덱과 영상 변환 | HTJ2K/JPEG XL의 라이브러리 경로와 앱 채택 여부 구분; 변환 중복, DX 극성, 압축 프레임 경계 조건 명시 | DICOM 지원, 아키텍처 |
| 화면 비율과 좌표 | 비정방형 픽셀 표시 비율, 좌표 변환 순서, 픽셀 조회와 측정 경계 정의 | DICOM 지원, API, 화면 |
| 재생 의미 | 획득 시간과 재생 시간 구분, trim/loop/sweep 기본 동작 명시 | DICOM 지원, API, 화면 |
| 프로젝트 복원과 저장 | 세션 ID와 영속 참조 분리, 저장 중 편집과 외부 변경 처리, 재연결 API 보완 | API, 아키텍처, ADR 0004 |
| 요구사항 일치 | 환자 정보 숨김 범위, 결정 시점, 초기화와 저장 상태의 의미 통일 | 제품 요구사항, 화면, 개발 계획 |
| 검증 가능성 | 요구사항·시험 연결 유지, 합성 기대값 추가, 필수 시험의 미실행을 합격에서 제외 | 개발과 검증 계획 |

기술 근거는 해당 절에 링크했다. DICOM의 `current` 문서와 라이브러리 문서는 갱신될 수 있으므로 구현 시에는 채택한 표준 판본·의존성 버전과 시험 결과를 함께 기록한다. 최소 macOS/CPU, 추가 코덱과 실제 성능은 위 미결정 목록의 개발 단계에서 확인한다.

문서 자체 검사에서는 내부 파일 링크 42개, 기능·품질 요구사항 19개의 시험 연결, 시험 ID 21개의 정의와 수치 확인 20개에 오류가 없었다. 표의 열 수와 코드 블록 경계도 확인했다. 앱 빌드·실제 DICOM·GPU·저장 동작 시험은 수행하지 않았다.
