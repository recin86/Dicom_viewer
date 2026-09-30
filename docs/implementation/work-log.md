# DICOM Viewer 작업 이력

이 문서는 작업별 변경과 검증·인수인계의 이력을 보존한다. 현재 상태는 [PROGRESS.md](../../PROGRESS.md), 작성 규칙은 [진행 기록 안내](README.md)를 따른다. 오래된 기록은 당시 관찰이며 현재 상태를 자동 보장하지 않는다.

## 2026-09-30 · SETUP-DOCS-AGENTS · 운영 준비

- 작성 AI: Codex 메인; 독립 검토와 역할 사례 시험은 서브에이전트에 배정.
- 제품 문서 0.2, AGENTS.md, 역할 TOML 4개와 스킬 6개 작성. 제품의 기술 제안·ADR 상태를 유지했다.
- 형식 검사와 당시 로컬 링크 68개를 통과했다. 임시 복사본에서 누락된 스킬/문서와 잘못된 TOML/YAML을 오류로 거부하는 것을 확인했다.
- `codex-cli 0.159.0 debug prompt-input`에서 루트 지침과 여섯 스킬 발견을 확인했다. 전체 프롬프트와 개인 설정은 프로젝트에 저장하지 않았다.
- 실제 임시 실행에서 호출 도구에 커스텀 역할 선택 인자가 없음을 확인했다. 일반 서브에이전트에 역할 지침과 스킬을 전달하는 대체 경로로 VERIFY-CORE, VERIFY-MACOS, VERIFY-FIXTURES, VERIFY-REVIEW를 수행했다.
- 각 역할은 공유 FFI 작성권, 앱/GPU 시험 미실행, 독립 golden 불일치, 읽기 전용 리뷰의 수정 제한 사례를 적용했다. 시험은 읽기와 판단만 수행했으며 제품 코드 시험은 아니다. 이 검증 전후 당시 파일 34개에 변경이 없었다.
- 앱 빌드·실제 DICOM·GPU·저장·성능은 `not-run`. 제품 코드와 fixture가 아직 없어 P0는 미착수다.

## 2026-09-30 · SETUP-GIT-HANDOFF · Git과 진행 기록

- 작성 AI: Codex 메인. 사용자 요청: Git 설정, 여러 AI 사이에 단계별 진행 상태와 재개 지점을 남기는 문서.
- 기존 Git 저장소가 없음을 확인하고 로컬 `main`을 생성했다. 기존 문서·역할·스킬과 `.gitignore`를 초기 커밋 `e4a9544aee89a6ca9f3af7aad59d32270c41b11c`로 기록했다.
- `.gitignore`에 빌드 산출물·로컬 비밀·원본 DICOM/로컬 자료 제외 경로를 추가했다. 합성·재배포 가능한 fixture 경로는 별도로 구분한다.
- PROGRESS.md, 진행 기록 안내와 이 이력을 추가하고 AGENTS.md·README·조정 스킬·단계 양식에 AI 작업 시작/중단/종료 시 갱신 규칙을 연결했다.
- 변경 범위는 Git과 문서·운영 지침이다. 제품 구현·지원 범위·기술 채택 상태는 변경하지 않았다.
- 최종 검증과 독립 리뷰 결과는 아래에 덧붙인다. 해당 기록 전에는 운영 지침 변경의 최종 검증 완료를 주장하지 않는다.
- 원격 저장소 URL은 사용자 확인 대기다. 로컬 Git은 준비되어 있고 원격에 전송한 파일은 없다. 다음 제품 작업은 사용자 개발 시작 요청에 따른 P0 계획과 기술·자료 실험이다.

## 2026-09-30 · P0-PLAN · P0 계획 작성

- 작성 AI: Claude (Cowork 세션). 사용자 요청: P0 계획 수립.
- [P0-tech-data.md](P0-tech-data.md) 작성: P0-ENV/DATA/CODEC/FFI/DIST/REVIEW 배정, 실행 순서, OneDrive 대응 규칙, 필요한 사용자 입력.
- PROGRESS의 P0 행과 현재 작업자 행을 계획 상태로 갱신. 기존 미커밋 변경(SETUP-GIT-HANDOFF)은 건드리지 않음.
- Cowork 셸이 Mac이 아닌 Linux VM이라 환경 명령은 실행하지 않음: 모든 실행 증거 `not-run`. 미커밋.
- 작업 중 이 세션의 git status가 Cowork VM에서 빈 `.git/index.lock`을 남겨 사용자 승인 후 삭제했다. 이후 Cowork VM에서의 Git 조회는 `GIT_OPTIONAL_LOCKS=0`으로 실행한다.
- 사용자 결정 반영: Intel 제외(OQ-01), App Store·유료 계정 없음(OQ-05 방향), 자료 없음(합성 우선), Xcode 없음(CLT+SwiftPM). README OQ 표·P0 계획·PROGRESS 갱신. `origin` 연결, `git ls-remote`로 원격이 비어 있음 확인, push 안 함.

## 2026-09-30 · P0-DATA-1 · 공개 시험 파일 1차 수집

- 작성 AI: Claude (Cowork 세션). 사용자 요청: 시험용 DICOM 파일 다운로드.
- pydicom 3.0.2 패키지의 test_files·charset_files와 pydicom-data 저장소의 data_store/data를 `local-data/pydicom/`에 복사(180개, 약 60MB). `/local-data/`는 .gitignore 대상이며 `git status --ignored`로 제외 확인.
- 출처·라이선스(MIT)·파일별 원출처 설명, 목록 CSV(SOP/TS/Modality/크기/프레임/SHA-256), 부족 자료 목록을 해당 폴더 README에 기록.
- 부족: 실제 CT 다중 슬라이스 시리즈, DX, 실제 크기 영상, 긴 US cine. 픽셀 디코딩 검증은 미실행(P0-CODEC).
- 추가: neurolabusc/dcm_qa_ct(BSD-2)의 GE 두부 CT 28장과 Philips 팬텀 S21610(151개 파일, 약 79MB)을 `local-data/dcm_qa_ct/`에 받음. gantry tilt·불균일 간격·확장자 없는 파일·혼합 시리즈 사례. 목록을 ver1.1 CSV(331개)로 갱신하고 `local-data/README.md` 작성.
- TCIA·NEMA·dclunie·Kitware는 Cowork VM과 클라우드 모두 egress 정책으로 차단(403). tilt 없는 CT, DX, 긴 US cine은 미확보.

## 2026-09-30 · P0-ENV · 개발 환경 점검

- 작성 AI: Claude (Cowork 세션). Cowork 터미널 제어가 클릭 전용이라 읽기 전용 점검 스크립트 `experiments/p0-env/check-env.sh`를 만들고 사용자가 실행했다. 결과 `experiments/p0-env/env-report.txt`.
- 결과: Apple M5, 16 GiB, macOS 27.0, CLT 27.0 + Swift 6.4 (Xcode 없음), rustc 1.95.0 aarch64, cmake 없음, python3 3.9.6. CLT만으로 Swift+AppKit+Metal 컴파일과 런타임 shader 컴파일 성공, 오프라인 `metal` 컴파일러 없음.
- P0 계획에 기준 환경(OQ-06 초안)과 후속 조치(rustup update, CARGO_TARGET_DIR, cmake 필요 여부, python 버전) 기록. 미커밋.

## 2026-09-30 · P0-FFI · 실험 코드 작성

- 작성 AI: Claude (Cowork 세션). `experiments/p0-ffi/` 작성: Rust crate(uniffi 0.32.2, thiserror 2, futures-channel 0.3, Cargo.lock 포함), SwiftPM 패키지(Xcode 없이 CLT), 실행 스크립트 run.sh, README.
- Cowork 클라우드(Linux x86_64, rustc 1.95.0)에서 Rust 단위 시험 2개 pass, uniffi-bindgen으로 Swift 바인딩 생성 확인. 확인 사항: 레코드 안 Vec<u8>는 Swift Data로 RustBuffer 경유 복사, 길이 Int32; &[u8]는 Swift Data 무복사 인자; UniffiInternalError는 fileprivate.
- Swift 코드는 Swift 툴체인이 없어 컴파일 미확인 → Mac에서 run.sh 실행 필요. 빌드 산출물은 ~/Library/Caches/dicom-viewer/p0-ffi/ (OneDrive 밖).
- 2026-09-30 Mac 실행(사용자): 빌드 성공(ld 검색 경로 경고만), 20개 check 모두 pass. 결과는 P0 계획 실행 증거 절. 메모리 회수 문제(64 MiB 반복 시 peak 2.95 GB, 이후 1 GB 잔류)는 후속 확인 항목.
- 메모리 후속(run.sh mem, 사용자 실행): 64 MiB 프레임 수신 시 호출당 약 1프레임씩 남음, autoreleasepool·pressure relief로 줄지 않음. 한 번 수신의 순간 peak는 3프레임. 원인 미확정, Rust 할당 계수 실험 예정.

## 2026-09-30 · MOVE-LOCAL · 프로젝트 폴더 이동

- 사용자가 프로젝트를 OneDrive에서 로컬 `~/Documents/Dicom_viewer`로 옮김. Git 이력·origin·local-data·실험 결과 유지 확인. 기기 간 공유는 GitHub로 한다.
- 공개 저장소이므로 로컬 경로가 들어가는 빌드 로그(`p0-ffi-build.log`, `p0-ffi-time.txt`)는 Git에서 제외.

## 2026-09-30 · P0-FFI-MEM2 · 메모리 원인 분리

- Rust 전역 할당 계수기와 Swift 단독 모사 변형 추가(`experiments/p0-ffi`), 사용자 Mac에서 `run.sh mem` 실행.
- 결과: Rust 할당·해제 수 일치(누수 없음). Swift 복사 과정 단독 모사는 증가 없음. 64 MiB 반복 전달에서만 호출당 약 1프레임 footprint 증가, 일부 시간 경과 후 감소 → 할당기 수준 해제 지연으로 추정. 한 번 전달 시 Rust 3장 + Swift 3장 규모의 순간 복사 발생.
- 다음: 실사용 크기 반복 시험 후 픽셀 전달 경로(UniFFI 유지 / C ABI 보조 경로 / UniFFI &mut [u8] 대기) 결정. 미커밋.

## 2026-09-30 · P0-FFI-REAL · 실사용 크기와 대안 픽셀 경로

- `run.sh real` 1차: 1 MiB CT·1.17 MiB US 반복은 footprint 일정, 16 MiB 반복은 호출당 16 MiB 증가.
- 대안 `FrameBuffer.copy_into`(Rust 보유 프레임 → Swift 소유 버퍼로 1회 복사) 추가 후 2차: 1/16/64 MiB 모두 footprint 일정, 전달 p50 0.02/0.45/1.86 ms. 픽셀 전달 경로 권고를 P0 계획 판단 절에 기록(ADR 0002·docs/04 반영은 리뷰 후).

## 2026-09-30 · HANDOFF-CLAUDE · Cowork 세션 종료

- 사용자가 이후 작업을 Codex로 진행하기로 해 Claude(Cowork) 조정을 종료. PROGRESS와 P0 계획의 인수인계 절을 현재 상태로 갱신.
- 다음 작업: P0-CODEC. 실행 중인 작업 없음.
