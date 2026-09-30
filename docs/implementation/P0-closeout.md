# P0 종료 준비 · DATA·FFI 계약·전체 검토

2026-09-30 (Asia/Seoul) · Task ID `P0-CLOSE-20260930` · 최초 조정 Codex/root → 조정 Claude(Cowork) · 상태 **done (P0 완료, 2026-09-30)**.

기준 `main` / `ea7e2b351fad35a1e8871e6e21bf226739913d67`. 기존 P0-CODEC 실험과 중앙 문서 3개가 미커밋이며 그대로 보존한다. 실행 중인 이전 작성 작업은 없다. commit/push는 이 작업에 포함하지 않는다.

목표는 [docs/06 P0 종료 조건](../06-development-and-validation.md)에 필요한 DATA manifest·부족 자료 계획과 FFI 픽셀 전달 계약을 검토하고, 기술 선택을 실제 증거와 함께 확정하는 것이다. 제품 구현·릴리스 지원 합격과 분리한다. 관련 OQ-01~06, FR-03/04/12, QR-01~06, T-03~05·T-06~08·T-11~13·T-20 사전 실험.

| Task | 작성자 | 허용 범위 | 목적 / 기준 | 상태 |
| --- | --- | --- | --- | --- |
| P0-DATA-CLOSE | dicom_fixtures / codec_reference 재사용 | 신규 experiments/p0-data/**; 생성 DICOM은 캐시 | 기존 공개 331+CODEC 합성 50 manifest와 docs/06 최소 자료 비교, 부족 합성 및 독립 golden 준비 | done (fixture 준비 pass) |
| P0-FFI-AUDIT | dicom_reviewer / codec_review 재사용 | 읽기 전용 | 기존 p0-ffi producer/consumer/생성기와 docs02/04·ADR0002 계약 대조 | done (Claude 재수행, A1~A8) |
| P0-FFI-CONTRACT | 메인; 필요 시 파일별 위임 | 신규 experiments/p0-ffi-contract/**, docs02/04·ADR0002 | 감사 결과에 따라 양쪽 경계를 실제 컴파일·시험, 검증한 픽셀 경로 명시 | done (Mac pass 11 / fail 0) |
| P0-DECISIONS | 메인 | README·docs03/06·ADR 및 중앙 기록 | OQ 최소 OS·연결·코덱·Enhanced 판단, 기존 지원 목표 유지 | done (OQ-01~04 확정) |
| P0-REVIEW | dicom_reviewer | 읽기 전용 | 최종 구현·DATA·FFI·결정과 P0 종료 근거 검토 | done (조건부 완료 → 조건 충족) |

메인이 중앙 진행 기록·공통 빌드·API 문서 작성권을 유지한다. 기존 CODEC source/results와 p0-ffi 실험은 변경하지 않고 후속 증거를 별도 폴더로 기록한다. 자료군 보완은 fixture 준비이며 제품 T 시험 합격으로 바꾸지 않는다. 생성 bytes·golden·원본·경로 있는 로그는 Git 밖 캐시에 둔다.

FFI의 API·단위·수명 기준은 [docs04](../04-core-api-and-data-model.md), 픽셀 의미는 [docs03](../03-dicom-support.md), 합격 기준은 [docs06](../06-development-and-validation.md)을 따른다. 제품의 포인터 대여·zero-copy는 이번 목표가 아니다. 기존 raw 주소 copy_into는 실험 근거로 보존하고 새 경로는 producer·Swift consumer·contract test를 같은 묶음으로 검증한다.

## Claude 인수 · 2026-09-30 (Asia/Seoul)

- Codex/root가 사용량 한도로 작업 중 중단. 중단 시점 실제 파일: `experiments/p0-data/`(prepare.py·README, 미실행, results 없음), `experiments/p0-ffi-contract/`(Cargo.toml·toolchain·bindgen·C 헤더만, Rust src·Swift·실행 스크립트 없음). P0-FFI-AUDIT 서브에이전트의 반환 결과는 저장소에 남지 않았다. 기준 HEAD `ea7e2b3` 그대로, 미커밋 파일은 모두 보존.
- 인수자: Claude(Cowork) 조정 담당. 위 배정 표의 모든 작성권(DATA 실행·FFI 감사 재실행·FFI-CONTRACT 구현·DECISIONS·중앙 기록)을 Claude가 이어받는다. Codex의 기존 CODEC 결과와 p0-ffi 폴더는 계속 동결한다.
- 실행 환경 제약: Claude는 Mac 셸을 직접 쓸 수 없다(Cowork Linux VM에서 사전 실행). macOS·Swift가 필요한 최종 실행은 사용자가 Mac 터미널에서 스크립트 한 줄을 실행하고, Claude가 결과 파일을 읽어 기록한다. Linux VM 실행은 사전 검증이며 대상 Mac 증거로 기록하지 않는다.

## 실행 증거와 최종 상태

착수 전 Git·문서 및 작성권 대조 pass. 아래는 Claude 인수 후 실행 결과다. Mac 실행은 모두 사용자가 대상 Mac 터미널에서 스크립트를 실행했고, Claude가 결과 파일을 읽어 대조했다.

| 항목 | 환경 | 명령 | 결과 | 상태 |
| --- | --- | --- | --- | --- |
| P0-DATA-CLOSE | Apple M5, macOS 27.0, CODEC venv Python 3.12.13·pydicom 3.0.2·numpy 2.5.3 | `~/Library/Caches/dicom-viewer/p0-codec/venv/bin/python experiments/p0-data/prepare.py` | 합성 38개·341 프레임·102,392,576 픽셀 readback 일치, 공개 331 원본·CODEC 보고서·목록 해시 불변, Linux VM 사전 실행과 합성 해시 38개 동일. [README](../../experiments/p0-data/README.md), [preparation.json](../../experiments/p0-data/results/preparation.json) | pass (fixture 준비만) |
| P0-FFI-AUDIT | 읽기 전용 | — | A1(임의 정수 주소 공개 메서드)~A8(문서 불일치). [계약 README](../../experiments/p0-ffi-contract/README.md) | done |
| P0-FFI-CONTRACT | Apple M5, macOS 27.0, Rust 1.98.1, Swift 6.4 CLT, UniFFI 0.32.2, 정적 링크 | `bash experiments/p0-ffi-contract/run.sh` | Rust fmt·시험 5·clippy·build pass; Swift C01~C10·C12 pass 11, C11 정보, fail 0, not-run 0. 64 MiB 복사 p50 1.09 ms, 복사 중 Rust 할당 0 | pass (P0 계약 실험) |
| P0-DECISIONS | 문서 | — | OQ-01 macOS 27.0·arm64(사용자 확인), OQ-02 UniFFI + 타입 있는 C 복사(ADR 0002 채택), OQ-03 baseline+charls+openjpeg-sys, OQ-04 Enhanced v0.2 유지. README·docs/02·03·04·06·ADR 반영 | done |
| P0-REVIEW | 독립 reviewer 서브에이전트(읽기 전용, 저장소 스냅샷+diff) | — | 차단 결함 없음, 조건 F1(C08 결과 재생성). 아래 처리 후 Mac 재실행으로 조건 충족 | done |

중간 실패와 수정(기록용): prepare.py의 단일 AT 태그 `TypeError`, Rust 1.98 clippy `chunks_exact_to_as_chunks`, Swift 배타 접근 오류, C08 detail 키 덮어쓰기(1차 JSON pass 10). 결과 파일에는 수정 후 최종 결과만 남아 있다.

### 독립 검토 발견과 처리

| ID | 심각도 | 내용 | 처리 |
| --- | --- | --- | --- |
| F1 | 중요(조건) | C08 결과 오염, 결과가 소스보다 오래됨 | detail 분리, run.sh 시작 시 이전 결과 삭제, 재실행: pass 11·소스 해시 일치 |
| F2 | 중요 | C07 버퍼 재사용으로 부분 복사 검출 불가 | 매 복사 전 sentinel 재충전 후 재실행 |
| F3 | 중요(P1) | 보유 handle의 Rust bytes가 캐시 예산 밖에서 생존 | docs/04·02에 기록. P1 계약에서 해제 규칙 또는 예산 계수를 정하고 T-13에서 계측 |
| F4 | 경미 | docs/04 FramePayload 표와 handle 모델 불일치, mask 생략 표현 | docs/04 수정 |
| F5 | 경미(P1) | 래퍼 전용 사용이 관례에 의존 | P1에서 C 모듈을 래퍼 모듈의 비공개 의존성으로 격리 |
| F6 | 경미 | C04 overflow 라벨 부정확 | 한도 초과와 실제 u64 overflow를 나눠 시험 |
| F7 | 경미 | C05 evict 반환값 미확인 | 확인 추가 |
| F8 | 경미 | OQ-03 제한 나열 불완전, JPEG Extended | README OQ-03에 CODEC 제한 표 링크, docs/03 JPEG 행 수정 |
| F9 | 경미 | OQ-06 저장 장치·전원 모드 없음 | 미기록임을 README에 명시, P2 성능 측정 전 보완(확인하지 않은 값은 적지 않음) |
| F10 | 경미 | 최대 동시 디코딩 수·단일 프레임 한도 미결정(docs/06) | P1/P2로 이월. 실제 decode·캐시 없이 정하면 근거가 없다. 현재 512 MiB 등은 실험값 |
| F11 | 경미 | 합성 자료의 의도적 비적합 미표시, 누락 사례 | condition 표시·gap 두 항목 추가, Mac 재실행(합성 DICOM 해시 불변) |
| F12 | 경미 | 결정을 검토보다 먼저 반영, OQ-01 사용자 확인 | 채택은 이 검토와 F1 재실행을 조건으로 했고 둘 다 충족. OQ-01은 사용자 확인(2026-09-30) 기록 |

### 종료 판정과 남는 항목

**P0 완료.** docs/06 종료 조건(대표 자료 manifest, 의존성 버전·feature 고정, 대상 Mac의 Rust 호출과 큰 bytes 왕복, OQ-01~04 확정, OQ-05 방향과 OQ-06 기준 환경 기록)을 충족했다. 제품 지원이나 릴리스 합격을 뜻하지 않는다.

계속 not-run/open인 항목:

- FFI·앱: 실제 `decode_frame`–handle 결합, 요청 generation·취소 경합(T-12), MTLBuffer와 GPU 완료 순서, 정식 T-11·T-13(handle 보유분 포함 예산), 최대 동시 디코딩 수와 단일 프레임 한도, 레코드 경로 footprint 누적의 근본 원인(채택 경로에는 해당 없음).
- CODEC: 저장 값 정규화, planar·YBR·Palette, 빈 BOT 다중 fragment, 손상 BOT/EOT·frame count 수락, JPEG Extended, public-316/328 Modality, FG oracle과 not-run 5건, 정식 T-03~T-05·T-13.
- DATA: 제조사 no-tilt CT, MR echo/time·Frame of Reference, 제조사 DX·VOI LUT, 실제 긴 US cine·보정 영역, 컬러 300프레임, 메타데이터·복구·표시 경계, IOD 적합성.
- 기타: OQ-06 저장 장치·전원 모드, 앱 번들·서명·Gatekeeper(P5).

Git: 사용자 요청으로 P0-CODEC(Codex 작업)과 P0-CLOSE 변경을 두 commit으로 나눠 커밋했다. push는 GitHub 인증이 있는 Mac에서 사용자가 한다. 다음 작업은 P1 계획 작성이며, 첫 계약 과제는 F3, F4 후속, F5다.
