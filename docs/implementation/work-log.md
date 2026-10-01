# DICOM Viewer 작업 이력

이 문서는 작업별 변경과 검증·인수인계의 이력을 보존한다. 현재 상태는 [PROGRESS.md](../../PROGRESS.md), 작성 규칙은 [진행 기록 안내](README.md)를 따른다. 오래된 기록은 당시 관찰이며 현재 상태를 자동 보장하지 않는다.

## 2026-10-01 · P1-COMMIT-20261001 · 사용자 요청으로 현재 작업 로컬 커밋

- 사용자 지시: "일단 여기까지 커밋". Codex/root가 `codex/p1-foundation`/기준 `c68c9208` 이후 native 표시·컬러 경계 준비·SC 컬러와 중앙 문서/검증 기록을 한 후속 커밋에 포함했다. 현재 실행 중인 소스 작성자 없음, core/app 작성권 반환 및 독립 reviewer 최종 결과 회수 확인. 커밋 식별자는 `git log -1`로 확인한다.
- 검토된 source39/generated3 hash와 현재 구현의 일치를 재확인, `git diff --check` pass, P0 diff 없음. 기존 debug/release 각각 Rust45·PIXEL18·DISPLAY26·COLOR29 pass 및 필수 리뷰 결함0을 보존했다. 이번에는 인수인계의 커밋 상태만 추가 갱신했고 제품 코드는 바꾸지 않았다.
- 실제 UI/전체 지원 not-run을 커밋 메시지와 인수 기록에 유지한다. raw 로그·생성 binding·binary·DICOM은 Git 제외, 원격 push 없음. 후속은 최신 실제 UI 회귀와 독립적인 Palette16 LUT 과업이다. 결과 JSON의 baseline/uncommitted는 시험 당시 상태를 나타내며 과거 snapshot은 재작성하지 않는다.

## 2026-10-01 · P1-COLOR-20261001 · native SC 컬러 자동 검증 완료

- 사용자 지시: "일단 다음단계진행". UI를 기다리지 않고 독립적인 SC컬러 producer/자동소비자 시험을 진행한다. DISPLAY 실제NSOpenPanel/presentation 회귀는 private컬러 수치계약의 의존성이 아니므로 분리하고 UI/전체지원 완료판정은 보류한다. 기준 c68c9208+이전DISPLAY/준비 미커밋변경 보존.
- [새 컬러 과업](P1-native-color.md)에 작성권/기존revision/독립literal/시험을 등록했다. core는 native/privatecolor/lib와Rust시험, app은새ViewerColorChecks만, main은Package/check/FFI필요변경/문서/fixture/결과를 맡는다. 최종reviewer는읽기전용. source작성범위를겹치지않고 기존App/Rendering/Bridge를보존한다.
- 구현: core `native.rs`·신규 `native_color.rs`·`lib.rs`, 신규 Swift ViewerColorChecks, Package/check 연결. RGB planar0/1·YBR_FULL planar0/1·even-width422 planar0를 RGBA8로 한 번 정규화. 기존 API/revision/generated3·App/Bridge/Rendering·fixture generator2/manifest와 P0는 보존.
- 실제 최종 자동 실행: `bash scripts/check.sh`·`--release` 각각exit0, fmt/clippy·Rust38+FFI7·PIXEL18·DISPLAY26·COLOR29 pass. 정상7종·오류19종과 source/원본hash·선형보간·W/L/invert무변화·확장payload budget·close/copy/GPUlastowner 확인. source39/gen3/fixture50/binary8/log2/report8은 [컬러JSON](results/P1-native-color.json). 양쪽 bundle strict/deep ad-hoc 서명·8실행파일arm64/minos27/staticRust 확인.
- core/app 작성권 반환·소스 동결. 독립 reviewer 최종 저장 근거 크기/hash·embedded JSON과 서명/링크 대조 pass, 필수 결함0. YBR 전체8-bit 조합 독자수치비교 최대차1로 허용범위 충족. 좁은 COLOR-1 자동 범위 완료, 실제 사용자 UI 회귀와 전체 지원은 별도not-run. 기존 DISPLAY/준비JSON은 당시snapshot으로 보존하며 현재 캐시binary로 역사적hash를 재해석하지 않는다. 변경은 앞선 작업과 함께 미커밋·push 없음.

## 2026-10-01 · P1-ADAPTER-PREP-20261001 · 다음 묶음 독립 준비 착수

- 사용자 요청: 다음 단계 진행. 실제 `codex/p1-foundation`/HEAD `c68c9208`와 이전 DISPLAY 미커밋 변경·반환 작성권을 대조했다. 현재 DISPLAY 최종 UI는 다시 확인해도 Mac 잠금으로 `not-run`이며 잠금 해제를 비동기 요청했다.
- [컬러·코덱 경계 준비](P1-color-boundary.md)에 별도 task와 작성권을 등록했다. core는 P0 실패와 다음 최소 adapter 범위 읽기 전용 조사, root는 독립 literal fixture writer/별도 cache/manifest, reviewer는 준비 결과 읽기 전용 검토를 맡는다. 현재 제품 소스/FFI/DISPLAY fixture·결과/P0 변경 없음.
- 의존 제품 구현은 DISPLAY 실제 회귀 뒤 진행한다. 조사·fixture 준비는 독립적으로 진행하며 준비 완료를 제품 색/codec 지원으로 판정하지 않는다. source와 UI 작업의 작성권은 main, 중앙 문서 작성권은 root다. 새 준비 변경은 미커밋이며 push 없음.
- 준비 실행: 별도cache에서 writer2회·pydicom3.0.2/numpy2.5.3/Python3.12.13 readback으로26개 preparation pass/0fail, 정상후보11/raw전용3 stored/RGB/RGBA literal 정확일치·negative15 metadata 경계·반복26byte일치. oracle오염/filebyte변경 두 주입은 각각 rgb_literal/file_hash와exit1을 검출. 초기USplanar/Paletteindex규칙과implicitVR검증 오판을 수정했고, reviewer가 C.8.5.6.1.2의 USnative Photometric 제약을 추가지적해 USYBR3개를 unsupported/rawreadback전용으로 분리했다(manifestrev2/v2cache, 이전오판이력보존). PythonAST/diff검사, 기존DISPLAY35/gen3/fixture24보존과P0동결 확인. [준비JSON](results/P1-color-preparation.json)에source2/fixture형식/hash/실제readback·controls를 기록했다. 독립 reviewer 최종hash 읽기전용검토 중.
- 최종 반환: reviewer는 source2·manifest2·fixture26/repeat26·readback/controls와실패주입report 크기/hash/내용을 대조했고, 독자 pydicom/BT.601/palette계산으로 raw14와negative15를 확인했다. 열린 필수결함0·준비완료. 검증CLI/fixture생성/빌드/앱기동/파일수정은 수행하지 않았다. 마지막 main CUA재시도까지3회 Mac잠금 유지. 독립준비만완료, COLOR제품/adapter거부 및 DISPLAY최종UI는not-run·완료보류. 실행 중인 소스 작성 없음·작성권 반환, 새로운4파일/중앙문서와기존DISPLAY는미커밋·push없음. 다음은 잠금해제→DISPLAY실제회귀/review/commit→컬러첫substep구현.

## 2026-10-01 · P1-DISPLAY-20261001 · 구현·자동 검증, 최종 UI 대기

- 완료한 선행 골격/PIXEL-1은 `c68c9208be771e366fe0824d0a7a8291eb679597`으로 커밋했고 직후 clean 확인, push 없음. 이후 묶음3 변경은 미커밋이며 기존 P0는 동결 유지.
- 구현: core DISPLAY-1 VOI·auto range·극성·padding·aspect·안전단위/diagnostics·동일입력SHA256·≤64KiB CPU reference, FFI/Swift immutable display bridge, AppKit native 파일 열기/상태복구·generation·Metal/shader/fit·확대/이동·CLI, sha2 lock·Package·fixture24·check 및 중앙 문서.
- 최종 자동 실행: macOS27.0.1/M5/16GiB에서 `bash scripts/check.sh`, `bash scripts/check.sh --release` 각각 fmt/clippy·locked Rust core28+FFI7·PIXEL18·Metal26·bootstrap·원본 hash 보존 pass. source35/generated3/fixture24/debug-release binary6/log2 해시 및 결과는 [P1-native-display.json](results/P1-native-display.json). 두 local ad-hoc bundle strict/deep signature·arm64/minos27/static Rust 직접 확인.
- 독립 reviewer 조건부 최종 반환: 근접 폭1 LINEAR·큰 SIGMOID 수치 overflow, 이전 전체 표시 상태 복구·stale failure, 제한 설명·window popup·texture bound·실제 presentation 재표시 수정 확인. 열린 필수 소스 결함0. source35/generated3/fixture24/binary6/log2/report6 크기·해시·실제 JSON 일치, pydicom13종 read-only 별도 파싱·서명/링크 직접 확인. reviewer는 재빌드·앱 실행·fixture 생성하지 않았고 실제 UI 미실행으로 완료 보류.
- 실제 UI: 마지막 재표시 수정 전 startup native drawable smoke는 두 profile pass. CUA 수동 NSOpenPanel 선택에서는 첫 frame이 보이나 Loading/disabled가 남는 문제를 발견. 후보의 실제 presentedTime>0 승인까지 연속 draw, Ready/Fail/새load/close 때 on-demand 복귀로 보완. 이후 자동26개는 pass지만 실제 panel/사용자설정복구·진단/RGB·최신 startup UI는 **not-run (Mac 잠금, 비동기 잠금 해제 요청)**. 완료 판정 보류.
- 인수: core/app 소스 작성 종료·main에 반환. 새 작성 없음. 잠금 해제 후 기존 앱 종료·최신 debug/release `--ui`, 실제 파일 선택 창→Ready, 사용자 대비/반전/확대/이동 뒤 encode실패→복구/재시도, 제한/RGB controls를 AX·screenshot/선택적safe trace로 확인하고 reviewer/해시를 갱신한다. 전체codec/LUT/Enhanced·회전/측정/PNG·성능/전체RSS·P5는 후속. 상세 재개 절차는 [표시 기록](P1-native-display.md).

## 2026-10-01 · P1-DISPLAY-20261001 · 커밋과 표시 착수

- 사용자 요청: 커밋하고 다음 단계 진행. reviewed 골격·PIXEL-1 변경 42파일을 `c68c920`으로 커밋, 이후 working tree clean 확인. push 없음. 이전 JSON은 검증 당시 상태로 보존한다.
- [표시 계획](P1-native-display.md)에 DISPLAY-1·작성권·native 단일 파일→표시 목표·T-04/T-11/T-12/T-16/T-21 부분 검증을 등록. core 표시 설명·CPU 기준, 앱 Metal/열기와 main FFI/bridge/공통 빌드를 분리 배정하며 최종 독립 리뷰 수행.
- 상태 running, 검증 not-run. 압축/Enhanced/다중frame·폴더/시리즈·측정은 후속.

## 2026-10-01 · P1-PIXEL-CONTRACT-20260930 · Codex 완료

- 사용자 요청의 다음 단계(P1 묶음 2) 완료. `codex/p1-foundation`/`ca9e8b8`와 골격 미커밋 변경을 보존. commit/push 없음, 모든 core/app/main/reviewer 배정 종료·작성권 반환.
- 변경: core 불변 frame·payload budget·bounded native adapter, FFI PixelSession/PixelHandle·weak ticket registry·C copy, Swift 별도 예산·불변 OwnedPixelFrame·detached 준비/복사·계약 CLI, C module/Package·internal bootstrap import, libc locked dependency, 합성 fixture generator·check/build, API/architecture/ADR·PROGRESS·P1 계획·[픽셀 기록](P1-pixel-contract.md)·[결과 JSON](results/P1-pixel-contract.json).
- 결정: cache eviction/close 뒤 살아 있는 Rust handle/C copy의 payload도 마지막 참조까지 예약을 유지. Swift 복사본은 별도 예산으로 계수. 새 목적지만 복사해 GPU 사용 중 writable 목적지 API는 제공하지 않음. 실제입력 결합을 위해 native legacy 단일 프레임만 제한적으로 읽고 unsupported는 명시 거부.
- 실제 최종 검증: macOS 27.0.1(26A434)/M5/16GiB/Rust1.98.1/Swift6.4에서 `bash scripts/check.sh`와 `--release` 각각 fmt/clippy·locked build·Rust core16+FFI6·Swift18·bootstrap·fixture10 원본 hash 보존 pass. debug/release 앱의 별도 UI smoke도 pass. source28/generated3/binary4 및 원시loghash를 기록함.
- 독립 reviewer: 필수 수정 결함 0. 소스·생성물·fixture·binary·log 전 hash 대조, strict ad-hoc signature·arm64/minos27/static Rust 직접 확인, pydicom3.0.2의 기존4fixture read-only stored/RGB readback 일치. 재빌드·앱 실행·파일 변경·fixture 생성은 하지 않았음.
- 초기 실패는 수정 후 재실행: Rust header length/JoinHandle, Swift import access/generated Error case, FFI lint. 개발용 bundle SIGKILL9·signature 오류는 실행파일 새inode교체/ad-hoc seal·strict verify로 보완. CLT 검색 경로 경고만 남음. P0 tracked 소스·결과 변경 없음.
- not-run: 전체 FramePayload/source/generation·취소, VOI·극성·종횡비·CPU/Metal/GPU 표시, 전체 codec·engine/parser/RSS 제한·성능, Swift 실제 malloc 실패 주입, CUA 시각 재관찰·P5 설치/다른Mac. Rust allocation 실패는 시험 주입으로 rollback 검증. 전체 P1/T-11/T-13 합격으로 확대하지 않음.
- 다음: P1 묶음 3의 VOI/표시 설명·source/request 계약·비동기 파일 열기·Metal 한 프레임 표시. 현재 앱 열기는 비활성화, bootstrap bool=false. 재현 명령은 위 check, GUI shell 포함 시 `--ui` 추가.

## 2026-09-30 · P1-PIXEL-CONTRACT-20260930 · Codex 착수

- 사용자 요청: 다음 단계. 기준 `ca9e8b8` + 기존 P1 골격 미커밋 변경, 브랜치 `codex/p1-foundation`. 기존 변경과 P0 증거를 보존한다.
- [픽셀 계약 계획](P1-pixel-contract.md)에 PIXEL-1의 live payload 예산·수명·C copy·Swift 소유권·실제 파일 결합과 작성권을 등록했다. core와 Swift는 기존 역할 에이전트에 분리 배정하고 main이 FFI·공통 빌드·통합을 담당한다. 독립 검토는 최종 소스에서 실행한다.
- 상태 running, 검증은 not-run. UI 열기·VOI/GPU 표시는 후속이다.

## 2026-09-30 · P1-FOUNDATION-20260930 · Codex 완료

- 범위: 사용자 요청의 1번(P1 계획·제품 골격) 완료. P1 전체는 진행 중. 기준 HEAD `ca9e8b8`, 브랜치 `codex/p1-foundation`, P1 변경은 미커밋이며 commit/push 없음.
- 배정: 일반 서브에이전트에 역할 TOML·스킬·작성권을 전달해 dicom_core(코어 2파일), macos_app(앱 4파일), dicom_reviewer(읽기 전용)를 실행했다. 최종 통합·빌드·기동·중앙 문서는 Codex/root가 수행했다. 실행 중 작성 작업 없음.
- 변경: Cargo workspace·lock·Rust toolchain, viewer-core/ffi 초기 연결, Swift package·ViewerBridge·AppKit 기본 창/메뉴·개발용 Info.plist, shared environment/build/check/run, .gitignore, README·docs02/04/06·진행 안내·PROGRESS와 [P1 계획](P1-single-frame.md), [결과 JSON](results/P1-foundation.json). 기존 P0 실험·결과는 동결 유지.
- 실제 검증: `bash scripts/check.sh --ui`(fmt·clippy all-targets/all-features·locked debug Rust/Swift build·Swift→Rust bootstrap·창/메뉴/열기 비활성/마지막 창 종료) pass. `bash scripts/build.sh release` 및 debug/release 개발용 앱의 bootstrap/UI smoke pass. Mach-O arm64/minos=27.0와 static Rust 링크 확인. CUA AX/screenshot으로 실제 기본 창 배치 관찰. source 해시 21개·두 binary 해시를 결과 JSON에 기록했다.
- 최초 native build는 CMake PATH 누락으로 fail. 기존 P0 CMake 4.4.3을 fallback으로 추가해 최종 명령 pass. CLT-only SwiftPM의 존재하지 않는 developer 검색 경로 경고는 기록하고 시스템 설정은 바꾸지 않았다.
- 독립 검토: 필수 수정 결함 0. reviewer는 source/generated binding/bridge/app, version/checksum guard, 해시·Mach-O·링크·로그·ignored artifact·P0 보존을 대조. 읽기 전용으로 재빌드/앱 실행하지 않았고 현재 Mac 잠금으로 live CUA 재관찰은 not-run; main의 앞선 실제 관찰과 구분했다.
- 기타 확인: shell syntax·Info.plist lint·git diff --check pass, 최종 변경 문서 링크 85개 누락 0. 원본 DICOM을 읽거나 변경하지 않았다.
- 미실행: 실제 DICOM/픽셀/GPU, 제품 메모리·수명·요청 경합, 전체 앱 조작과 다른 Mac·설치·서명·Gatekeeper. 골격 결과로 해당 T 항목 전체를 합격 처리하지 않는다.
- 다음: P1 계획 묶음 2(보유 handle 메모리 예산·FramePayload API·비공개 C copy/Swift 래퍼·T-11/T-13) 후 회색조 adapter/한 프레임 표시. 현재 전역 bool은 프레임 capability가 아니다.

## 2026-09-30 · P1-FOUNDATION-20260930 · Codex 착수

- 사용자 요청: 이전 현황 보고의 1번(P1 계획과 제품 코드 골격) 진행. 실제 프로젝트는 `~/Documents/Dicom_viewer`; 채팅 cwd의 OneDrive 폴더는 비어 있으므로 실제 저장소에서 작업한다.
- 기준 `ca9e8b8`, 착수 시 clean. 원격 main=`49b444e`를 조회했고 로컬이 3 commit 앞섬을 확인. 새 브랜치 `codex/p1-foundation`에서 기존 P0 실험·결과를 보존한다.
- 작성 AI/세션: Codex/root. [P1 계획](P1-single-frame.md)에 task·BOOTSTRAP-1·파일 작성권·후속 묶음을 등록했다. 일반 서브에이전트에 역할 TOML·스킬·배정을 전달하는 방식으로 core와 app shell을 위임한다.
- 변경 허용 범위: 제품 workspace·FFI·Swift package/bridge·공통 빌드·계획/중앙 기록, core 및 앱 작성 파일은 분리. 현재 running; 최종 빌드·기동·독립 리뷰와 남은 미실행은 종료 기록에 추가한다. commit/push는 이번 완료 조건에 포함하지 않는다.

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
