# DICOM Viewer 작업 이력

이 문서는 작업별 변경과 검증·인수인계의 이력을 보존한다. 현재 상태는 [PROGRESS.md](../../PROGRESS.md), 작성 규칙은 [진행 기록 안내](README.md)를 따른다. 오래된 기록은 당시 관찰이며 현재 상태를 자동 보장하지 않는다.

## 2026-09-30 · P0-CLOSE-20260930 · Claude(Cowork) 인수와 P0 종료

- 인수: Codex/root가 사용량 한도로 중단. 중단 시점 실제 상태를 대조했다. prepare.py·README는 미실행, p0-ffi-contract는 Cargo.toml·헤더 초안만 있었고, FFI 감사 결과는 남지 않았다. 기준 `ea7e2b3` 유지, 기존 미커밋 변경은 보존. 작성권 전체를 Claude가 인수([P0-closeout](P0-closeout.md)).
- 작업 방식: Claude는 Mac 셸 입력이 불가해(터미널은 클릭 전용 권한) Cowork Linux VM에서 Python·Rust를 사전 실행하고, Mac 실행은 사용자가 스크립트 한 줄을 실행했다. Linux 결과는 사전 검증으로만 기록했다.
- 변경: `experiments/p0-data/prepare.py`(AT 태그 버그 수정, 검토 반영), `experiments/p0-data/README.md`, 신규 `experiments/p0-ffi-contract/`(Rust lib, C 헤더, Swift 래퍼·검사, run.sh, README, results), README OQ-01~04·OQ-06 비고, ADR 0002 채택과 ADR 목록, docs/02·03·04·06, P0-closeout·P0-tech-data·PROGRESS. 기존 CODEC·p0-ffi 소스와 결과는 수정하지 않았다.
- 실행(대상 Mac): DATA 준비 exit 0, 합성 38개 전 픽셀 readback 일치. FFI 계약: Rust fmt·시험 5·clippy·build pass, Swift C01~C10·C12 pass 11 / fail 0 / not-run 0 / info 1. 중간 실패 4건(AT 태그, clippy 새 lint, Swift 배타 접근, C08 결과 키 덮어쓰기)은 수정 후 재실행.
- 검토: 독립 reviewer 서브에이전트(읽기 전용, 스냅샷+diff)가 조건부 완료로 판정. F1~F12 처리는 P0-closeout 표에 있다. F3·F5는 P1 첫 계약 과제.
- 결정: OQ-01 macOS 27.0·arm64(사용자 확인), OQ-02 UniFFI + 타입 있는 C 복사, OQ-03 baseline+charls+openjpeg-sys, OQ-04 Enhanced v0.2 유지.
- 상태: **P0 완료**. 사용자 요청으로 CODEC·P0-CLOSE를 두 commit으로 커밋, push는 사용자 몫. 실행 중 작업 없음. 다음: P1 계획(범위: 한 프레임 표시, 첫 과제 F3·F4 후속·F5와 CODEC 제한 해소 계획).

## 2026-09-30 · P0-CLOSE-20260930 · Codex 착수

- 사용자 요청: 다음 단계 진행. 기준 `main`/`ea7e2b3`, 기존 CODEC 미커밋 변경과 이전 결과 보존. 활성 구현 작성자 없음 확인.
- 메인은 [P0 종료 준비](P0-closeout.md)를 작성하고 DATA 보완·FFI 계약 감사·양쪽 사전 실험·OQ 결정·전체 P0 검토를 진행한다. 기존 CODEC 및 p0-ffi 폴더는 동결; 신규 실험과 관련 문서만 작성한다.
- 현재 running, 미커밋. 실제 실행·검토 결과와 다음 재개 지점은 종료 시 아래 기록으로 추가한다.

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

## 2026-09-30 · P0-CODEC-20260930 · Codex 착수

- 조정 AI: Codex / root. 기준 `ea7e2b3`, clean working tree; 이전 Claude 종료와 작성권을 확인하고 인수.
- 허용 범위: `experiments/p0-codec/` 신규 실험과 P0 계획·이력·PROGRESS. Rust 실험과 독립 Python 참조를 분리 위임, 마지막에 독립 reviewer 및 메인 통합 검증.
- 시스템 Rust 1.98.1 확인. uv Python 3.12·독립 코덱·cmake는 저장소 밖 캐시에 준비. 실제 자료는 public local-data만 읽으며 원본/환자 정보/로컬 경로를 일반 보고서에 포함하지 않음.
- 현재 진행 중, 미커밋. 종료 시 실제 결과·남은 작업으로 아래 후속 기록 추가 예정.

## 2026-09-30 · P0-CODEC-20260930 · Codex 완료와 인수인계

- 작성권: 메인은 중앙 문서·실험 실행/빌드 기록/메모리 스크립트, `dicom_core`는 실험 Rust, `dicom_fixtures`는 Python 합성·독립 참조, `dicom_reviewer`는 읽기 전용 검토. 이번 도구의 agent_type으로 세 커스텀 역할을 호출했다. 초기 세션의 역할 인자 미노출 기록은 당시 상황으로 유지한다.
- 변경: 신규 `experiments/p0-codec/`(고정 manifest/lock/toolchain, 생성기·참조·CLI, 실행 스크립트, 버전·feature·license·전체 결과·해시 증거)와 P0 계획·PROGRESS·이력. 제품 API/ADR·기존 p0-ffi는 수정하지 않음.
- 실제 Mac M5/16 GiB/macOS 27.0에서 Rust 1.98.1, dicom-rs 0.10.0, uv Python 3.12.13의 고정 참조 패키지로 실행. CharLS 정적 C++(격리 CMake), OpenJPEG 정적 C와 Rust 포트 각각 빌드; 전역/Homebrew 환경은 바꾸지 않음. named Rust toolchain과 캐시 venv를 준비함.
- 공개 331 + 합성 50(정상 42·손상 8), 6개 조합 각 381개 실행. 최종 baseline 253/59/10/59, charls 264/53/5/59, openjp2·openjpeg 각각 273/39/10/59, combined·combined-c 각각 284/33/5/59 (pass/fail/not-run/not-applicable). 원본 전후·목록 SHA 일치, 합성 SHA 조합 간 동일, 소스·binary·보고서 해시 대조 pass.
- fmt, Rust 시험 3개, clippy -D warnings, 참조 신뢰 경계 시험 8개, Python/Bash 구문 검사, 6개 release build pass. 메인 최종 `run.sh all` exit 1은 픽셀·변환·프레임 제한과 oracle not-run을 정직하게 반영한다. 결과를 pass로 고치지 않았음.
- 독립 reviewer의 재실행 출력·손상 오류 분류·직접 프레임 수락·비트 metadata LUT 할당·원본/목록 hash 강제 판정·F64 산술 허용치·FG oracle 오판 지적을 수정 후 최종 재실행. public-309는 stored와 프레임 일치, FG Modality만 not-run. 손상 BOT/EOT 수락 등 upstream 관찰은 제품 과제로 유지. 문서의 정확한 to_vec_with_options API와 Rust wrapper MIT / bundled CharLS BSD-3-Clause 라이선스 구분도 보완.
- RLE 32×512×512 whole/single-frame 별도 프로세스 각 3회: peak RSS 166.86~168.84 / 20.63~20.64 MiB, 6회 전 픽셀·원본 해시 pass. 앱 표시·긴 cine·동시 요청·GPU 성능 시험이 아님.
- 권고: baseline+charls+openjpeg-sys. 저장 값 부호·유효 비트, 컬러·프레임 경계 보완 필요. 참조와 C OpenJPEG의 codec 공유 한계도 기록. 원본·합성 DICOM·golden·target·raw diagnostics는 ignored local-data 또는 저장소 밖 캐시에만 유지.
- 종료 상태: CODEC **조사 완료**, 제품 지원 및 P0 전체 완료 아님. 앱/GPU/FFI 통합·정식 T-03~05·T-13·하위 OS·긴 cine not-run. 전체 P0 독립 검토도 남음. 변경 전체 미커밋, commit/push 없음, 기준 HEAD `ea7e2b3` 유지. 실행 중인 구현 작업 없음.
- 다음: DATA 최소 자료·합성 계획 보완 → `$dicom-ffi-contract`로 기존 copy_into 계약 검토 → 전체 P0 REVIEW → OQ 확정·ADR 0002/docs04 반영 → P1 계획. [실험 보고서](../../experiments/p0-codec/README.md)와 [P0 계획](P0-tech-data.md)이 재개 근거다.
