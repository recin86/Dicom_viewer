# DICOM Viewer 개발과 검증 계획

이 문서는 개발 순서와 단계별 완료 기준을 정의한다. 먼저 대표 자료와 Mac 빌드 경로의 불확실성을 확인한 뒤, 한 프레임 표시에서 탐색·측정·저장으로 확장한다. 화면에 영상이 나타나는 것과 수치·순서·단위가 정확한 것을 별도로 검증한다.

문서 버전 0.2 · 작성·검토일 2026-09-30 · 상태 검토·보완한 설계 초안. 기간과 인력은 아직 정하지 않았다. 아래 수치는 **제안 목표**이며 앱 시험 결과는 모두 미측정이다.

## 단계와 종료 조건

| 단계 | 구현과 조사 | 종료 조건 |
| --- | --- | --- |
| P0 기술과 자료 확인 | 지원 OS/CPU, 실제 DICOM 특성, dicom-rs 코덱, UniFFI 연결, 배포 방식 조사 | 대표 자료 manifest, 의존성 버전 및 feature 고정, 대상 Mac에서 Rust 호출과 큰 bytes 왕복 실험; OQ-01~04 확정, OQ-05 배포 방향과 OQ-06 기준 환경 기록 |
| P1 한 프레임 표시 | 코어 adapter, 픽셀 계약, Swift 앱, Metal 표시와 입력 | 회색조·컬러 기준 프레임 표시, VOI와 좌표 검증, 오류와 MainActor 경계 확인 |
| P2 검사 탐색 | 메타데이터 인덱싱, display set, 스택, cine, 캐시와 취소 | 네 modality의 지원 범위 자료 탐색, 오래된 결과 방지, 자원 제한과 성능 기준 환경 기록 |
| P3 연구 도구 | OQ-07~08을 시작 전에 결정하고 비교, 거리·각도·ROI, 메모, 주석 편집과 취소 구현 | 수치 기준 시험 합격, 원본 좌표 유지 |
| P4 저장과 내보내기 | 프로젝트, 원본 재연결, CSV, PNG, 복구 | 저장 round-trip, 충돌·실패·원본 변경 시험, 작업 복원 |
| P5 개인용 배포 | OQ-09를 시작 전에 결정하고 release 빌드, 앱 패키징, 서명 정책 적용, 깨끗한 사용자 환경 시험 | 실제 지원 Mac/OS의 열기부터 저장까지 통합 시험, OQ-05 배포 방식 검증, 의존성 포함 확인, 릴리스 지원 표와 제한 공개 |

P0의 실험 코드는 의사결정 근거로 사용한다. 검증 없이 그대로 제품 경계나 API로 굳히지 않는다. P1부터 P4까지 통합된 결과를 v0.1 후보로 삼고, P5를 통과한 범위만 릴리스 지원으로 표시한다.

MPR과 Enhanced CT/MR 확장은 v0.2 후보이다. 대표 자료에서 필수로 판명되면 P0에서 요구사항과 단계를 조정한다. 범위 변경 없이 개발 중 조용히 필수 기능을 제외하지 않는다.

## 시험 자료 관리

작은 합성 자료는 계산값과 경계 조건을 검증하는 데 사용하고, 사용 권한을 확인한 비식별 실제 자료는 제조사와 코덱 호환성 시험에 사용한다. P0에서 공개 331개와 CODEC 합성 50개·DATA 합성 38개를 준비했다([P0 종료 기록](implementation/P0-closeout.md)). 자료 준비와 제품 시험 통과는 구분한다. 공개 데이터라는 이유만으로 재배포 가능하다고 가정하지 않는다.

각 fixture manifest에는 다음을 기록한다.

- fixture ID, 출처, 사용·재배포 조건, content SHA-256.
- SOP Class UID, Transfer Syntax UID, Modality, 크기와 프레임 수.
- 픽셀 형식, signedness, photometric interpretation, lossy 여부.
- 공간 또는 시간 차원의 의미, 변환과 보정 정보의 존재 여부.
- 기대 성공 기능과 의도된 실패 기능, 기대 픽셀·좌표·단위.
- 기대값을 만든 방법, 독립 decoder 또는 참조 뷰어 이름과 버전.
- 실행한 앱, Rust, Swift/Xcode, codec 버전 및 실제 OS/CPU/GPU 환경.

테스트 보고서에는 fixture ID를 사용한다. 로컬 원본 경로와 환자 식별 정보가 포함된 자료를 소스 저장소에 자동 추가하지 않는다. 합성 자료, 재배포 가능한 자료, 외부 로컬 자료를 구분한다.

## 최소 자료 구성

| 자료군 | 필요한 사례 |
| --- | --- |
| CT | signed/unsigned, 음수 intercept, 비단위 slope, oblique orientation, 뒤섞인 파일명, 중복 위치, 불균일 간격 |
| MR | 여러 시리즈, 같은 위치의 다른 echo/시간, 누락 geometry, 서로 다른 Frame of Reference |
| X-ray | CR, DX for Presentation, MONOCHROME1/2, VOI LUT, 보정 있음/불명, 검출기 간격만 있음 |
| US | 회색조와 RGB/YBR/Palette, 정지 영상, 고정/가변 frame time cine, 시간 정보 없음, 보정 영역이 다른 화면 |
| 코덱 | 채택한 각 Transfer Syntax의 정상 자료, 빈 Basic Offset Table, 허용된 다중 fragment 프레임, Extended Offset Table, 손상 픽셀, 미지원 코덱 |
| 메타데이터 | 한글과 UTF-8, 누락 UID, 동일 UID의 다른 내용, 긴 sequence, 대형 값 |
| 복구 | 접근 거부, 파일 삭제/이동/교체, 저장 중 실패, future project schema |
| 표시 경계 | 비정방형 픽셀, Pixel Aspect Ratio만 있는 영상, 전부 padding/균일 영상, 잘못된 spacing·orientation |

고급 기능의 자료도 일부는 미지원 동작을 검증하기 위해 포함한다. 예를 들어 Enhanced MR을 아직 표시하지 않는 단계에서는 이를 일반 MR 스택으로 오인하지 않는 것이 합격 조건이다.

## 시험 목록

| ID | 시험 | 합격 기준 | 연결 요구사항 |
| --- | --- | --- | --- |
| T-01 | 파일과 폴더 입력 | 확장자 없는 파일, 하위 폴더, 혼합 파일, 취소와 재시도에서 정상 자료를 잃지 않음 | FR-01, FR-12 |
| T-02 | 식별과 메타데이터 | UID 중복/누락을 구분하고 한글과 태그 조회 결과가 기대값과 일치 | FR-02, FR-06 |
| T-03 | 코덱과 픽셀 해석 | 채택한 각 형식을 golden pixel과 비교; 압축 프레임 경계와 offset table 검증; 미지원 형식은 명시적 오류 | FR-03, QR-01 |
| T-04 | 회색조 변환 | signedness, rescale 중복 방지, LUT, VOI 경계, 균일/전부 padding, DX 극성이 기준 결과와 일치 | FR-03, FR-05, QR-01 |
| T-05 | 컬러 | RGB/YBR/Palette 색 패치, planar layout과 크기가 기준 결과와 일치 | FR-03, QR-01 |
| T-06 | 공간과 정렬 | 위치 기반 순서, LPS, 비등방 spacing, 불완전 geometry 제한, 회전/뒤집기 후 선택 좌표가 기대값과 일치 | FR-04, FR-05, QR-01 |
| T-07 | 프레임 의미 | 파일과 프레임 수를 혼동하지 않고 echo/시간 혼합을 잘못된 볼륨으로 만들지 않음 | FR-02, FR-04 |
| T-08 | cine | 시간축, frame index, loop/sweep, trim, 대체 시간 근거와 정지 시 프레임이 정확 | FR-04, QR-02 |
| T-09 | 측정 보정 | patient/calibrated/unverified/detector/scanned/px 상태를 구분하고 US에 잘못된 mm 결과를 만들지 않음 | FR-08, QR-01 |
| T-10 | ROI와 각도 | 포함 픽셀, padding 제외, 모집단 SD와 퇴화 도형 처리가 기준값과 일치 | FR-08, QR-01 |
| T-11 | FFI와 버퍼 수명 | 길이와 endian 검증, 세션 종료와 cache eviction 후 반환 payload 유효, 반복 열기에서 누수 없음 | QR-02, QR-03 |
| T-12 | 요청과 취소 | 순서를 바꿔 완료시켜도 최신 요청만 표시, close와 cancel 경합에서 중복 terminal 없음 | FR-12, QR-02 |
| T-13 | 캐시와 제한 | 캐시·대기·진행 중 버퍼 예산 준수, source 변경 시 무효화, 초대형 프레임·압축 해제 출력·깊은 sequence에 제한 적용 | FR-12, QR-03 |
| T-14 | 프로젝트 저장 | round-trip, 저장 중 편집의 dirty 유지, 쓰기·교체 실패, 파일 revision 충돌과 schema migration에서 마지막 유효 문서 보존 | FR-09, FR-10, QR-05 |
| T-15 | 원본 재연결 | 인덱스 삭제와 새 세션에서도 영속 참조 복원, 파일 이동/다른 이름 저장 후 동일 내용 연결, 같은 UID의 다른 내용에는 주석 적용 안 함 | FR-10, QR-05 |
| T-16 | 화면과 입력 | 활성 뷰, 1/2/4분할, Retina, 마우스/트랙패드, 텍스트 focus, undo가 명세와 일치 | FR-05, FR-07, FR-08, FR-09 |
| T-17 | CSV와 PNG | 단위·값·frame number, quoting, 자유 텍스트 처리, 오버레이 선택과 PNG 표시가 기대 결과와 일치 | FR-11 |
| T-18 | 실패 복구와 진단 | 손상 파일/권한 거부가 다른 자료 열람을 막지 않고 일반 로그에서 원문 식별 정보가 나오지 않음 | FR-12, QR-07 |
| T-19 | 원본 보존과 오프라인 | 열람·측정·저장 전후 원본 SHA-256 동일, 네트워크 차단 환경에서 기본 기능 동작 | QR-04 |
| T-20 | 빌드와 설치 | 지원 대상으로 발표할 각 환경에서 release 앱 기동, 기본 자료 열람·저장, 외부 개발 도구 없이 실행 | QR-06 |
| T-21 | 표시 비율과 좌표 경계 | Pixel Aspect Ratio만 있는 영상도 비율 유지, mm 측정 비활성화, fit/회전/반전/보간/Retina/PNG가 같은 변환 사용 | FR-03, FR-05, FR-11, QR-01 |

시험의 목적은 함수 호출 여부보다 사용자 결과와 수치 계약을 확인하는 것이다. 실행하지 않은 항목은 통과가 아닌 미실행으로 기록한다.

T-02에는 file meta와 dataset UID 불일치, T-05에는 이미 RGB인 decoder 출력의 중복 색변환 방지, T-08에는 trim 이후 원본 번호 유지와 가변 간격 sweep, T-12에는 가져오기 도중 grouping 변경을 포함한다. T-14/T-15는 주석이 없는 뷰 상태만 저장한 프로젝트와 해시 계산 중 원본 변경도 시험한다. T-16/T-18은 환자 정보 숨김의 목록·라벨·오버레이 범위와 남아 있는 원문 정보의 설명을 확인한다.

## 정확성 기준 제안

**Lossless 정수 디코딩**은 fixture의 독립 golden 배열과 모든 픽셀이 같아야 한다. lossy 자료는 같은 입력에 대한 신뢰할 수 있는 참조 디코딩 결과와 비교하고 decoder 간 허용 차이를 사례별로 정한다. lossy 이전 원본과 픽셀 완전 일치를 요구하지 않는다.

**수치 계산**은 CPU의 F64 기준 경로에서 검증한다. 합성 좌표와 거리의 오차는 `max(1e-6 mm, 기대 절댓값 × 1e-9)`, 통계 오차는 `max(1e-6, 기대 절댓값 × 1e-9)`를 초기 목표로 한다. 이는 구현의 수치 오차 기준이며 실제 영상의 해상도나 임상 측정 정확도를 뜻하지 않는다.

각도는 `max(1e-6 degree, 기대 절댓값 × 1e-9)`, sampled area는 `max(1e-6 면적 단위, 기대 절댓값 × 1e-9)`를 사용한다. 픽셀 수와 프레임 번호는 정확히 일치해야 한다. 유한 좌표의 화면→원본 round-trip 허용오차는 원본 기준 1e-6 pixel로 제안한다. 프레임 시간 파싱·합산의 수치 오차와 실제 재생 스케줄 지연은 별도로 측정한다.

**화면 변환**은 색관리 전 offscreen 출력에서 CPU와 Metal 결과를 비교한다. GrayF32LE 입력과 동일한 VOI를 사용한 8비트 출력은 채널당 최대 1 단계 차이를 초기 허용치로 제안한다. 색공간과 보간 조건을 고정해야 하며 실제 모니터의 보정 성능을 검증한 것으로 표현하지 않는다.

다음 합성 사례를 구현 시 추가한다. 현재 존재하는 fixture가 아니다.

| 사례 | 입력과 기대 결과 |
| --- | --- |
| 비등방 픽셀 좌표 | origin=(10,20,30), row direction=(1,0,0), column direction=(0,1,0), row spacing=0.7, column spacing=0.4일 때 pixel (2,3)은 (10.8,22.1,30) mm |
| Rescale과 padding | 저장 값 24/1024/2024, slope=1, intercept=-1024는 -1000/0/1000; padding으로 지정한 저장 값 0은 통계에서 제외 |
| ROI 통계 | 위 세 유효 값의 평균은 0, 모집단 SD는 약 816.496580927726, 유효 개수는 3 |
| VOI 임계값 | LINEAR center=0, width=1에서 입력 -1은 최솟값, 입력 0은 최댓값; 폭 1에서 0으로 나누지 않음 |
| 프레임 번호 | API index 0과 DICOM frame number 1, 마지막 프레임 index N-1과 표시 번호 N의 round-trip |
| 취소 경합 | A 요청 후 B 요청, B 완료 후 A 완료를 강제로 발생시켜 B 영상·라벨·주석이 유지됨 |
| 표시 종횡비 | width=100, height=100, row/column spacing=0.7/0.4이면 회전 전 영상 경계 높이/너비는 1.75; Pixel Aspect Ratio=7/4만 있어도 같은 표시 비율이나 단위는 px |
| 픽셀 조회 경계 | x=-0.5는 열 0, x=0.5는 열 1, x=width-0.5는 범위 밖; Linear 표시에서도 원본 픽셀 조회값 유지 |
| VOI 함수와 자동 범위 | LINEAR_EXACT c=0,w=2에서 -1/0/1은 0/0.5/1; SIGMOID x=c는 0.5; 균일값 a의 자동 window는 극성 적용 전 0.5 |
| DX 극성 | 동일한 정규화 VOI 출력 0/1에서 MONOCHROME2+IDENTITY는 0/1, MONOCHROME1+INVERSE는 1/0; 사용자 반전은 그 결과를 한 번 뒤집음 |
| 비등방 각도 | 꼭짓점 (0,0), 다른 두 점 (1,0)/(1,1), row spacing=2, column spacing=1이면 약 63.434948822922도; PixelOnly라면 45도 |
| 타원 ROI 경계 | 중심 (1,1), rx=ry=1인 타원은 3×3 영상에서 5개 중심 포함; 그중 1개 padding, row/column spacing=0.7/0.4이면 valid=4, excluded=1, sampled area=1.12 mm² |
| 시간과 trim | Frame Time Vector=[0,40,60] ms의 첫 프레임 기준 시각은 [0,40,100]; trim=2..3의 재생 경과 시간은 [0,60], 저장 프레임 번호는 2/3 |
| 저장 중 편집 | document revision 7을 저장하는 동안 8로 편집하면 receipt는 7이며 현재 상태는 변경됨; 재시작 후 세션 ID가 달라도 영속 프레임 참조 복원 |

실제 뷰어와의 비교는 방향, 프레임 순서와 사용성 검증을 보완한다. 서로 다른 자동 window나 보간으로 화면이 다른 경우 계산 기준을 먼저 맞춘다. 참조 뷰어 하나의 스크린샷만을 유일한 정답으로 삼지 않는다.

## 성능 목표 제안

P0에서 기준 장비를 지정한다. Apple Silicon/Intel, 메모리, GPU, macOS, 화면 해상도와 배율, 저장 장치, 전원 모드 및 release 빌드 설정을 기록한다. 지원하겠다고 정한 하위 장비에서도 시험한다. 현재 특정 장비에서 달성한 결과는 없다.

| 동작 | 초기 목표 | 측정 조건 |
| --- | --- | --- |
| 단일 CT/MR 파일의 첫 프레임 | p95 2초 이내 | 로컬 SSD, 512×512 비압축 단일 파일, 앱 자체 캐시 비움 |
| 캐시된 스택 이동 | p95 50 ms 이내 | 512×512, 선택 입력부터 해당 프레임 표시까지 |
| W/L 또는 pan 갱신 | 처리·렌더링 p95 16.7 ms 이내, 입력부터 표시 p95 33.4 ms 이내 | 이미 GPU에 올라간 프레임, 60 Hz 화면, 합의한 해상도; 두 지표를 분리 측정 |
| US cine | 30 fps 자료를 목표 속도로 재생 | 640×480 컬러, 300프레임, 준비된 데이터; 누락 없이 실제 fps와 지연 기록 |
| 취소와 뷰 전환 UI 반응 | p95 100 ms 이내 | 코덱 내부 종료 시간과 별도로 UI 응답 측정 |
| 캐시 기본 예산 | CPU 512 MiB, GPU 256 MiB | 8 GiB 이상 장비의 출발점 제안, 전체 process 메모리는 별도 기록 |

메모리 예산은 라이브러리 내부 버퍼, in-flight payload, GPU 리소스와 앱 자체 메모리까지 모두 같다는 뜻이 아니다. 단계별 할당과 peak resident memory를 기록한다. 최대 동시 디코딩 수와 단일 프레임 한도도 P0 실험에서 정한다.

위 목표에 못 미치면 시간을 디코딩, FFI 전달, GPU 업로드와 표시로 나눠 원인을 찾는다. 사용자 경험에 영향이 있는 목표 변경은 근거와 함께 기록한다. 성능을 맞추기 위해 프레임, 픽셀 정밀도나 측정 정확도를 묵시적으로 낮추지 않는다.

캐시가 비어 있는 측정과 준비된 측정을 분리한다. 운영체제 파일 캐시를 통제하지 못하면 OS cold start라고 쓰지 않는다. 각 시나리오를 충분한 표본 수로 반복하고 p50/p95, 실패 수, peak memory와 반복 횟수를 보고한다. 기본 30회 이상을 출발점으로 삼되 변동성이 크면 측정 계획을 조정한다.

캐시 이동·W/L·pan의 종료점은 해당 frame reference와 표시 상태가 실제 presentation된 시점이다. GPU 제출 시점을 표시 완료로 대신하지 않는다. 60 Hz 화면의 표시 대기를 고려해 처리 예산과 입력→표시 지연을 위 표에서 분리했다. cine는 첫 표시부터 마지막 표시까지의 간격, 프레임 누락·중복 수와 스케줄 지연을 기록한다. 목표 fps 허용 편차는 ±5%를 출발점으로 하고 P2에서 확정한다. 30회 표본의 p95는 예비 측정으로 표시하며 릴리스의 상호작용 시나리오는 기본 100회 이상 관측한다.

## 빌드와 배포

Rust 문서는 macOS 대상으로 aarch64-apple-darwin과 x86_64-apple-darwin을 설명한다. Rust target의 존재만으로 앱의 최소 macOS와 전체 의존성 지원이 결정되지는 않는다. Xcode/SwiftUI/Metal 및 C/C++ codec 요구사항을 함께 검증한다. [Rust macOS targets](https://doc.rust-lang.org/rustc/platform-support/apple-darwin.html)

P0에서 Rust toolchain, Cargo.lock, UniFFI runtime/generator, Xcode와 Swift 버전, 추가 codec 버전을 고정한다. Swift Package 의존성이 있으면 Package.resolved도 관리한다. Rust, 앱과 네이티브 의존성의 deployment target을 일치시킨다.

P0 종료(2026-09-30)에서 고정한 값: Rust 1.98.1(aarch64-apple-darwin), UniFFI 0.32.2 runtime/generator, Swift 6.4 Command Line Tools와 SwiftPM(Xcode 없음), dicom-rs 0.10.0 baseline + charls + openjpeg-sys(각 Cargo.lock은 [P0-CODEC](../experiments/p0-codec/README.md)·[P0-FFI-CONTRACT](../experiments/p0-ffi-contract/README.md)). 지원 대상은 Apple Silicon과 macOS 27.0 이상(OQ-01)이며 제품의 Rust·Swift·네이티브 codec deployment target은 27.0으로 맞춘다. P0 FFI 실험 두 개는 deployment target 14.0으로 빌드했으므로 그 값은 제품 기준이 아니다. Intel은 지원하지 않으므로 아래 범용 패키징 문단은 현재 적용되지 않는다.

검증 자동화는 Rust format/lint/test → 코어 기준 영상 시험 → FFI 계약 시험 → Swift/Metal 빌드와 시험 → release 패키지 smoke test 순서로 설계한다. macOS 앱과 GPU 시험은 실제 macOS 환경에서 수행한다. Windows/Linux에서 통과한 코어 시험으로 macOS 통합을 대체하지 않는다.

P1 PIXEL-1(2026-10-01): `bash scripts/check.sh`와 `--release`는 fmt/clippy, Rust core 16+FFI 6, 실제 native 합성 DICOM→Swift 계약 18, bootstrap과 원본 hash 보존을 검증한다. 별도 debug/release 앱 UI smoke도 실행했다. [결과](implementation/results/P1-pixel-contract.json)는 소스·바이너리·fixture hash와 macOS 27.0.1 환경을 기록한다. T-03~05의 좁은 native 변환, T-11의 payload 수명과 T-13의 payload 예산 일부에 해당한다. 요청 generation·GPU 완료·전체 parser/codec/engine 한도·RSS와 정식 설치는 미검증으로 유지한다.

개인용 설치는 일반 `.app` 패키지를 목표로 한다. Apple Silicon/Intel 모두 지원할 경우 각 아키텍처 라이브러리와 모든 codec 의존성을 검사하고 적절한 범용 패키징을 수행한다. Intel 지원을 실제 Intel에서 검증했는지 Rosetta에서만 검증했는지 구분한다.

서명, Sandbox, notarization과 배포 채널은 OQ-05에서 정한다. 개발 중 로컬 실행과 다른 Mac으로 배포하는 경우를 구분하고, 배포 방식을 확정할 때 Apple의 최신 지침을 다시 확인한다. 인증서나 개발자 계정이 이미 준비됐다고 가정하지 않는다. [Apple macOS 배포 공증 안내](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)

릴리스에는 실제 지원 OS/CPU, codec feature 목록, DICOM 지원 표, 알려진 제한, 설치 방법과 제3자 라이선스 고지를 포함한다. 개발 도구가 설치되지 않은 사용자 환경에서 앱을 열고 최소 자료를 열람·저장해 본다.

## 릴리스 합격 조건

- 릴리스 대상 범위의 T-01~T-21 필수 사례가 모두 pass이다. fail 또는 not-run인 필수 사례가 있으면 해당 범위의 릴리스를 통과시키지 않는다. 적용 대상이 아닌 사례는 not-applicable과 이유를 기록하며, 미실행을 예외로 바꾸어 합격시키지 않는다.
- 방향, 단위, 픽셀 변환, 원본 연결, 저장 손상에 관한 미해결 오류가 없다.
- 필수로 정한 자료군마다 검증 자료와 결과가 존재한다. 파일 한 개의 성공을 전체 modality 지원으로 확대하지 않는다.
- 지원하지 않는 입력과 부분 지원의 사용자 표시가 실제 구현과 일치한다.
- 성능 결과가 기준 환경과 함께 기록되고 허용하지 않은 UI 정지와 지속적인 메모리 증가가 없다.
- 원본 DICOM의 해시가 유지되고 저장·재연결·내보내기 결과를 다시 읽어 확인했다.

## 결과 기록 형식

각 실행 기록에는 날짜, commit 또는 build ID, 의존성 manifest, 환경, fixture manifest revision, 시험 ID와 사례 ID, 요구사항 ID, 예상값, 실제값, pass/fail/not-run/not-applicable, 관련 결함을 포함한다. not-applicable에는 대상 범위에서 제외되는 근거를 적는다. 성능에는 표본 수와 분포를 추가한다. 설계 문서의 목표 표를 실행 결과로 덮어쓰지 않고 별도 검증 기록을 연결한다.

문서 0.2 검토는 표준·라이브러리 근거 대조, 내부 링크와 요구사항·시험 ID 연결, 추가한 합성 사례의 수치 확인을 대상으로 한다. 이 문서 검토와 T-01~T-21의 앱 시험은 별개이며 실제 앱 시험 결과는 개발이 진행된 뒤 추가한다.
