# DICOM Viewer 코어 API와 데이터 모델

이 문서는 Rust와 Swift 사이에서 주고받을 데이터, 작업 수명, 오류와 저장 형식을 정의한다. 프레임을 파일과 분리하고, 픽셀의 변환 단계와 좌표 단위를 명시해 화면과 계산의 일관성을 유지한다.

문서 버전 0.2 · 작성·검토일 2026-09-30 · 상태 검토·보완한 설계 초안. 아래 타입과 함수는 구현을 위한 개념 계약이며 컴파일 가능한 Rust/Swift 선언이나 확정 ABI가 아니다. UniFFI로 표현 가능한 구체 타입은 P0에서 검증한다.

## 공통 규칙

- 공개 ID는 문자열 기반의 불투명 식별자로 전달한다. Swift가 내부 의미를 분해하지 않는다.
- 앱 API의 프레임 인덱스는 0부터 시작한다. DICOM의 1부터 시작하는 프레임 번호는 입출력 adapter에서 명시적으로 변환한다. 화면에는 1부터 표시한다.
- 거리의 기본 단위는 mm, 시간은 ms, 각도는 degree이며 필드 이름이나 타입에 단위를 포함한다.
- `null` 또는 optional 값은 알 수 없음을 뜻한다. 0, 빈 문자열과 동일하게 취급하지 않는다.
- 날짜와 시간은 원문, 파싱 결과, timezone 근거를 구분한다. timezone이 없는 촬영 시각에 Mac의 시간대를 자동 부여하지 않는다.
- 메타데이터와 픽셀 결과는 immutable snapshot으로 전달한다. 동일 데이터의 변경은 revision으로 구분한다.
- 대형 목록은 pagination을 사용한다. 새 인덱싱으로 목록이 바뀌면 snapshot revision 또는 갱신 토큰으로 일관성을 관리한다.

## 주요 모델

| 모델 | 핵심 필드 | 의미 |
| --- | --- | --- |
| SourceRecord | source_id, locator_id, observed_revision, content_hash?, state | 실제 파일의 위치와 내용 상태 |
| StudySummary | study_id, study_instance_uid?, subject_display?, date?, modality_set, counts | 탐색용 검사 요약 |
| SeriesSummary | series_id, study_id, series_instance_uid?, description?, modality, support_summary | 시리즈 요약 |
| InstanceRecord | instance_id, source_id, sop_instance_uid?, sop_class_uid, transfer_syntax_uid, frame_count | 한 DICOM SOP 인스턴스 |
| FrameRef | instance_id, frame_index, source_revision | 세션 안에서 특정 원본 프레임을 식별 |
| FrameDescriptor | frame_ref, width, height, pixel_info, geometry?, timing?, display_descriptor, capabilities | 디코딩 요청과 조작에 필요한 정보 |
| DisplaySet | display_set_id, series_id, navigation_kind, ordered_frames, dimensions, grouping_revision, diagnostics | 함께 탐색할 프레임 집합 |
| Measurement | measurement_id, persistent_frame_ref, geometry, result?, calibration, algorithm_version | 원본 프레임에 연결된 주석과 수치 |
| PersistentViewState | persistent_frame_ref, display_set_selection, display settings | 세션을 다시 만들어도 복원 가능한 화면 상태 |
| ProjectDocument | schema_version, project_id, document_revision, sources, measurements, notes, layout, active_view_id, view_states | 연구 작업의 영속 저장; view_states는 PersistentViewState 목록 |

Patient ID나 환자명을 앱 내부 전역 고유 키로 사용하지 않는다. 서로 다른 source에서 같은 환자 식별 문자열이 나올 수 있으므로 UID와 source 관계를 유지한다. UID가 없는 자료도 source ID로 추적하고 누락 상태를 별도 보존한다.

## 프레임과 탐색 모델

`navigation_kind`는 `Still`, `SpatialStack`, `TemporalSequence`, `UnorderedFrames` 중 하나를 기본으로 한다. 후속 다차원 지원은 별도 차원 선택과 그 결과인 display set으로 표현한다. 모든 시리즈를 단일 3D 배열로 저장하지 않는다.

`ordered_frames`의 각 항목은 FrameRef이며 파일 위치 목록이 아니다. `dimensions`에는 공간, 시간, echo 등 해석한 축과 해석 근거를 넣는다. 알 수 없는 차원은 이름을 추정해 채우지 않는다.

프레임별 capability는 `can_display`, `can_window`, `can_probe`, `can_measure_distance`, `can_measure_angle`, `can_compute_roi`, `has_patient_geometry` 및 제한 이유를 포함한다. 측정 가능 여부와 물리 보정 상태는 분리한다. `can_cine`와 시간 근거는 DisplaySet에 속하며 한 프레임의 속성만으로 결정하지 않는다. UI는 Modality 이름 대신 이 capability로 도구를 활성화한다.

`FrameTiming`은 기록된 상대 시각과 기준점, frame_delay_ms?, 값의 원문·유효성을 보존한다. DisplaySet의 `PlaybackTiming`은 playback_offsets_ms, timing_source, is_estimated, trim 범위, 재생 방식과 마지막 프레임 유지 시간을 가진다. 대체 재생 시각을 기록된 획득 시각 필드에 넣지 않는다. 시간·trim·반복 규칙은 [DICOM 지원 명세](03-dicom-support.md)를 따른다.

서로 다른 Frame of Reference의 공간 연동은 등록 변환이 없으면 비활성화한다. 같은 Frame of Reference라도 orientation과 위치가 유효한지 별도로 확인한다. v0.1 비교는 기본적으로 독립 조작이다.

## 좌표와 표시 상태

`FrameGeometry`는 origin_lps_mm, row_direction, column_direction, row_spacing_mm, column_spacing_mm, frame_of_reference_uid?, provenance, validity를 가진다. orientation이나 spacing이 없으면 필드를 optional로 남기고 공간 기능을 제한한다.

`MeasurementCalibration`에는 row/column_spacing_mm?, calibration status, 근거 태그와 제한을 별도로 둔다. geometry가 없더라도 유효한 2D 간격에 따른 측정은 가능하다. `DisplayAspect`는 pixel_height_over_width와 근거·추정 여부를 담고 양의 유한 값만 허용한다. 이 표시 비율만으로 물리 보정 상태를 올리지 않는다.

`PixelPoint`는 열 x와 행 y의 0기반 픽셀 중심 좌표이며 소수 좌표를 허용한다. Swift viewport는 화면 point, backing pixel, 원본 PixelPoint를 구분한다. Retina 배율을 측정 배율로 사용하지 않는다.

`ViewState`는 display_set 참조와 grouping revision, 실제 표시 FrameRef, zoom_mode, zoom, pan, rotation_quarter_turns, flip_horizontal, flip_vertical, user_invert, selected_voi, interpolation, overlay_visibility를 가진다. zoom_mode는 Fit 또는 Manual이며 Fit에서는 화면 크기에 맞춰 zoom을 재계산한다. 기본 interpolation은 Linear, 픽셀 확인용 선택은 Nearest로 제안한다. selected_voi는 임시 목록 번호만이 아니라 함수와 파라미터 또는 원본 LUT 식별 근거를 포함한다.

화면 좌표는 좌상단 원점, 오른쪽 x와 아래쪽 y인 macOS point로 정규화한다. 초기 변환 계약은 다음과 같다.

```text
image_center = ((width - 1)/2, (height - 1)/2)
A = diag(1, pixel_height_over_width)
screen_point = viewport_center + zoom × R × F × A × (pixel_point - image_center + pan)
```

F는 원본 영상의 수평·수직 뒤집기, R은 화면에서 시계방향 90도 단위 회전이다. pan은 원본 픽셀 단위의 변위이며 zoom은 비율 보정 후 수평 픽셀당 화면 point이다. 변환과 역변환을 영상·주석·hit test·PNG가 공유한다. fit은 픽셀 중심뿐 아니라 바깥 경계 `[-0.5, width-0.5] × [-0.5, height-0.5]`까지 포함한다. Retina backing scale은 최종 렌더링 해상도에만 적용한다.

픽셀 조회는 역변환한 좌표가 `-0.5 ≤ x < width-0.5`, `-0.5 ≤ y < height-0.5`일 때 `floor(x+0.5), floor(y+0.5)`의 저장 픽셀을 사용한다. 범위 밖은 값 없음으로 반환하고 가장자리 픽셀로 몰래 고정하지 않는다. 픽셀 조회에는 화면 보간을 적용하지 않는다.

좌표 변환 규칙은 [DICOM 지원 명세](03-dicom-support.md)를 따른다. 주석은 화면 좌표로 저장하지 않는다. 회전과 확대 후에도 동일한 원본 위치를 가리켜야 한다.

## 픽셀 전달 계약

반환 모델 `FramePayload`는 아래 필드를 갖는다. payload는 한 프레임을 나타내며 전체 시리즈 복사를 기본 API로 제공하지 않는다. [ADR 0002](adr/0002-uniffi-and-pixel-buffers.md) 채택 후 `FramePayload`는 Rust가 보유한 불변 프레임의 UniFFI 객체(handle)이다. 아래 필드 중 bytes와 valid_mask는 값으로 들어 있지 않고, handle의 복사 연산으로 Swift 버퍼에 받는다(아래 메모리 소유권). 나머지 필드는 handle에서 조회한다.

| 필드 | 계약 |
| --- | --- |
| frame_ref | 요청한 source revision을 포함 |
| request_context | request_id, viewport_id, generation을 응답과 함께 보존 |
| payload_revision | decoder와 정규화 정책 변경을 구분 |
| width, height | 양의 정수, 크기 곱 overflow 검증 |
| pixel_format | GrayF32LE 또는 RGBA8 |
| row_stride_bytes | GrayF32LE는 width × 4, RGBA8은 width × 4인 연속 행 버퍼로 시작 |
| bytes | row_stride_bytes × height 길이. Swift 소유 버퍼로 한 번 복사해 받는다(아래 메모리 소유권) |
| valid_mask | 회색조는 width × height 바이트, 0은 무효 또는 padding, 1은 유효; 모두 유효하면 생략 가능. 생략은 mask 길이 0으로 표현하며 Swift 래퍼는 nil을 돌려주고, 이때 mask 복사 요청은 NoMask 오류다. RGBA8은 mask가 없다 |
| value_domain | GrayF32LE는 ModalityApplied, RGBA8은 DisplayColor |
| unit | HU, arbitrary, 명시 단위 또는 unknown; 근거 포함 |
| display_descriptor | VOI와 기본 극성 등 표시 설명 |
| display_aspect | pixel_height_over_width와 근거·추정 여부 |
| diagnostics | lossy 이력, 추정 또는 제한된 정보 |

GrayF32LE는 little-endian IEEE 754 32비트 부동소수점이다. signed/unsigned 원본 해석 및 지원 Modality 변환을 적용했으며 VOI와 최종 반전은 적용하지 않은 상태다. Swift가 slope/intercept를 다시 적용하지 않는다. non-finite 변환 결과는 valid_mask에서 제외하고 이유를 기록한다.

F64에서 유한하지만 F32 변환 시 overflow로 무한대가 되는 값은 padding으로 숨기지 않고 UnsupportedTransform으로 표시를 제한한다. valid_mask=0인 원소의 bytes는 유한한 0으로 채워 GPU에 NaN/Inf를 보내지 않는다. 출력 지점에 가장 가까운 원본 픽셀의 mask가 0이면 사용자 반전과 무관한 배경으로 처리한다. 유효한 위치의 Linear 보간은 유효 이웃의 가중치만 정규화하고, CPU 기준 렌더러도 같은 규칙을 쓴다. 통상적인 F32 반올림 오차는 표시 정확성 시험에서 다루며 측정은 F64 경로를 유지한다.

RGBA8은 R,G,B,A 순서이며 기본 alpha는 255이다. 색상 변환과 palette 적용은 Rust에서 끝낸다. 초기 컬러 표시의 출력 색공간 가정은 명시하고, ICC profile을 해석하지 못하는 자료에는 프로파일 기반 색 일치를 보장하지 않는다. 구체적인 Metal texture 형식과 출력 색공간은 P1의 기준 영상 시험으로 고정한다.

`DisplayDescriptor`는 사용 가능한 VOI 선택지, 기본 선택, 각 함수의 파라미터 또는 LUT, 해석된 기본 표시 극성, 자동 VOI 여부와 근거를 담는다. renderer가 원본 태그를 읽거나 IOD 규칙을 다시 판단하지 않는다. 사용자 반전은 별도 ViewState에 유지한다.

원본 픽셀과 정밀한 Modality 변환은 Rust가 보유하거나 필요 시 다시 읽는다. ROI와 픽셀 조회는 이 경로를 사용해 계산하고, GPU의 보간된 색이나 F32 표시 버퍼를 원본 수치로 역변환하지 않는다.

## 메모리 소유권

[ADR 0002](adr/0002-uniffi-and-pixel-buffers.md) 채택안(P0 종료 2026-09-30)을 따른다. `decode_frame`의 결과는 Rust가 보유하는 불변 프레임의 UniFFI handle이며, 위 표의 bytes 외 필드와 불투명 copy ticket을 제공한다. bytes와 valid_mask는 타입 있는 C 복사 함수로 Swift 소유 버퍼에 정확히 한 번 복사한다. Rust 포인터는 Swift로 나가지 않고, Rust는 Swift 목적지 포인터를 보관하지 않는다.

- 목적지 길이는 bytes는 row_stride_bytes × height, mask는 width × height와 정확히 같아야 한다. 오류(만료된 ticket, null, mask 없음, 길이 불일치)는 목적지에 쓰지 않는다. 경계 안의 panic은 상태 코드로 격리한다.
- Swift 코드는 C 함수를 직접 부르지 않고 안전 래퍼만 사용한다. 래퍼는 호출 동안 handle 수명을 연장하고, 정확한 크기의 버퍼를 할당하거나 배타적 버퍼·shared `MTLBuffer`를 길이 검사 후 채운다.
- 이미 받은 handle과 복사된 Swift 버퍼는 Rust cache eviction·세션 close와 무관하게 유효하다. handle과 캐시가 모두 해제되면 ticket은 만료되고 재사용되지 않는다.
- handle을 보유하는 동안 Rust 프레임은 eviction·close 뒤에도 해제되지 않는다. 이 bytes가 캐시 바이트 한도 밖에서 살아남지 않도록, P1 계약에서 "복사 직후 handle 해제" 또는 "살아 있는 handle의 bytes를 진행 중 버퍼 예산으로 계수" 중 하나를 정하고 T-13에서 계측한다(P0 종료 검토 F3).
- P0 계약 실험의 증거와 한계는 [P0-FFI-CONTRACT](../experiments/p0-ffi-contract/README.md)에 있다. 실제 decode·요청 generation·GPU 사용과의 결합은 P1 계약 시험에서 확인한다.

Swift는 Metal 업로드를 위해 byte storage를 사용하는 동안 해당 storage를 유지한다. 비동기 command buffer가 사용하는 리소스를 먼저 해제하지 않는다. Rust 메모리를 Swift allocator로 해제하거나 반대로 해제하지 않는다.

shared `MTLBuffer`를 목적지로 쓸 때는 해당 범위를 사용하는 GPU command buffer가 없을 때만 복사한다. borrowed byte API(예: UniFFI의 `&mut [u8]` 인자)를 도입할 때는 채택한 UniFFI 버전의 지원 방향과 수명을 확인해야 한다. 현재 설계는 Rust → Swift 출력의 zero-copy에 의존하지 않는다. 출력 공유를 최적화하려면 별도 buffer handle, retain/release, GPU 완료 시점 계약을 설계한다. [UniFFI byte buffers](https://mozilla.github.io/uniffi-rs/latest/types/bytes.html)

## 공개 작업 API 제안

다음 표는 의미를 정의한다. 함수명과 구체적인 비동기 바인딩은 변경할 수 있지만 입력, 결과, 취소와 오류 의미는 함께 갱신해야 한다.

| 작업 | 입력 | 결과 및 성격 |
| --- | --- | --- |
| create_engine | EngineConfig | engine handle, 짧은 초기화; 파일 전체 스캔 없음 |
| get_capabilities | 없음 | 실제 빌드 버전, codec와 구현된 기능 목록; 개별 입력의 지원 판정은 별도 |
| start_import | SourceLocator 목록, ImportOptions | ImportJob handle; 백그라운드 인덱싱 |
| read_import_events | job, after_sequence, limit | 진행, 발견 요약, 실패 및 terminal 상태 |
| cancel_import | job | idempotent 취소 요청 |
| list_studies | filter, cursor, limit | StudySummary page와 snapshot revision |
| list_series | study_id, cursor, limit | SeriesSummary page |
| open_series | series_id | SeriesSession과 DisplaySet 요약; 무거운 작업은 비동기 |
| list_frames | session, display_set_id, cursor, limit | FrameDescriptor page |
| decode_frame | session, FrameRef, RequestContext | 비동기 FramePayload 또는 ViewerError |
| prefetch_frames | session, FrameRef 목록 | 제한된 낮은 우선순위 요청; 결과는 캐시로 수집 |
| cancel_request | request_id | idempotent 취소 요청 |
| probe_pixel | session, FrameRef, PixelPoint | 원본 값, 변환 값, 단위, 유효성; 필요 시 비동기 디코딩 |
| evaluate_measurement | session, FrameRef, MeasurementGeometry, measurement_id, geometry_revision | 필요 시 비동기; 요청 식별 정보·도형 revision, 보정 상태와 계산 결과 |
| read_tags | instance_id, query, cursor, value_limit | 제한된 TagEntry page; pixel bytes는 자동 반환하지 않음 |
| load_project | SourceLocator | 비동기 ProjectDocument, 파일 revision token, source resolution 결과 |
| resolve_project_sources | project, source별 후보 SourceLocator | 비동기 내용 검증; 연결됨/누락/권한 필요/내용 불일치 상태와 새 세션 참조 |
| save_project | ProjectDocument snapshot, destination, SavePrecondition | 저장 receipt, 저장한 document_revision과 새 파일 revision token; 비동기 파일 작업 |
| export_measurements | 선택된 결과, destination, options | CSV 저장 receipt |
| close_session | session | 진행 요청 취소, 새 작업 거부, 남은 참조 수명 정리 |
| shutdown_engine | engine | 모든 작업 정리 후 완료; UI 종료와 연동 |

PNG 생성은 실제 표시 파이프라인을 공유하는 Swift renderer에서 수행한다. 저장 결과와 메타데이터 선택은 앱 모델이 관리한다. 측정 CSV의 값과 단위 생성은 Rust가 담당한다.

EngineConfig는 CPU/GPU 전달 예산과 입력·디코딩 제한을 명시한다. 임의로 큰 page limit, 프레임 범위 밖의 인덱스, NaN 좌표와 잘못된 도형은 InvalidArgument로 거부한다. 공간 보정 불가처럼 예상 가능한 기능 제한과 API 입력 오류를 구분한다.

## 요청과 취소

`RequestContext`는 request_id, viewport_id, generation, priority를 포함한다. request_id는 engine 수명 동안 고유하며 viewport generation은 해당 뷰의 선택이 바뀔 때 증가한다.

응답은 요청 시점의 context를 유지한다. 프레임·세션·source revision 또는 grouping revision 변경도 generation 변경에 포함한다. window/level 같은 표시 전용 변경에는 디코딩 generation을 올릴 필요가 없으며 도착한 픽셀에 현재 ViewState를 적용한다. 목록 pagination은 고정 snapshot을 사용하고 만료된 cursor에는 SnapshotExpired와 처음부터 갱신할 방법을 제공한다.

요청은 Queued → Running → Completed, Failed 또는 Cancelled로 전이한다. terminal 상태는 한 번만 확정한다. 취소와 완료가 경합하면 이미 확정된 terminal 결과를 유지한다. 결과가 늦게 도착해도 UI의 generation 검사는 항상 수행한다.

cancel은 best-effort 자원 중단이며 즉시 모든 코덱 작업이 멈춘다는 보장이 아니다. callback을 사용하는 구현에서도 UI thread를 직접 호출하지 않는다. 진행 이벤트는 묶거나 합칠 수 있지만 파일별 실패 결과와 최종 요약은 잃지 않는다. 이벤트 sequence가 보존 범위를 벗어나면 최신 snapshot을 반환하는 복구 경로를 둔다.

세션 close 이후에는 새 요청에 SessionClosed를 반환한다. 진행 중 작업은 세션 내부 참조를 소유하고 정상 종료 시 해제한다. Swift에 이미 반환된 payload handle과 그 handle에서 복사한 Swift 버퍼의 수명은 세션 close와 독립적이다.

## 오류 모델

`ViewerError`는 code, stage, user_message_key, retryable, source_id?, frame_ref?, safe_details를 갖는다. 상세 원문과 로컬 파일 경로를 기본 오류 메시지에 넣지 않는다.

| code | 의미 | UI 기본 동작 |
| --- | --- | --- |
| InvalidArgument / SnapshotExpired | 잘못된 요청 또는 만료된 목록 snapshot | 입력 수정 또는 목록 새로 고침 |
| IoDenied / SourceMissing | 파일 접근 불가 또는 파일 없음 | 권한 확보 또는 위치 다시 지정 |
| InvalidDicom | 파싱 실패 | 해당 파일 실패 기록 |
| UnsupportedSopClass | 영상 의미 해석 미지원 | 메타데이터 조회 가능 여부 표시 |
| UnsupportedTransferSyntax | 포함된 decoder가 없음 | 코덱 형식과 미지원 안내 |
| UnsupportedPixelFormat / UnsupportedTransform | 픽셀 또는 필요한 표시 변환 미지원 | 정상 영상처럼 표시하지 않음 |
| DecodeFailed | 지원 경로의 실제 디코딩 실패 | 파일별 실패, 재시도 여부 표시 |
| AmbiguousGeometry | 공간 정보가 불충분하거나 충돌 | 공간 기능 제한, 가능한 2D 열람 유지 |
| InvalidCalibration | 물리 측정 근거 불충분 | px 측정 또는 측정 불가 |
| SourceChanged | 인덱싱 이후 원본 revision 변경 | 재인덱싱과 주석 연결 확인 |
| ResourceLimit | 크기나 메모리 제한 | 원인과 제한 표시 |
| Cancelled / SessionClosed | 작업 취소 또는 닫힌 세션 | 일반 실패 알림 없이 상태 갱신 |
| ProjectVersionUnsupported / SaveConflict / SaveFailed | 프로젝트 저장 계열 오류 | dirty 상태 유지, 다른 이름 저장 등 제공 |
| InternalError | 예기치 않은 내부 오류 | 안전한 진단 ID와 복구 동작 |

## 측정 데이터

`MeasurementGeometry`는 Distance 두 점, Angle 세 점(가운데 점이 꼭짓점), RectangleROI 두 모서리, EllipseROI 중심과 x/y 반축 길이로 시작한다. ROI는 원본 픽셀 축에 정렬되며 임의 회전 도형은 초기 범위 밖이다. 모든 좌표는 원본 PixelPoint이다. 각도는 보정된 동일 평면의 물리 좌표에서 0~180도로 계산하고, 물리 보정이 없으면 픽셀 좌표 각도임을 명시한다. 길이가 0인 선분이 포함된 각도는 정의되지 않은 결과다. 거리·각도 점은 영상 경계 안에 있어야 하며 유효한 동일 점의 거리는 0으로 허용한다.

ROI 경계 위의 픽셀 중심은 포함하는 규칙으로 시작한다. 사각형과 타원의 영역 검사는 원본 좌표에서 수행하고 이미지 밖은 잘라낸다. 통계의 분모는 유효 픽셀 수이며 모집단 표준편차를 사용한다. 면적은 유효 픽셀 수에 기반한 sampled area로 명명하고, 도형의 기하학적 면적과 구분한다.

사각형은 정규화한 min/max 경계 안의 중심을, 타원은 `((x-cx)/rx)^2 + ((y-cy)/ry)^2 ≤ 1`인 중심을 포함한다. 폭·높이 또는 반축이 0 이하인 ROI는 유효 도형으로 확정하지 않는다. excluded_count는 영상 안의 포함 중심 중 padding·무효 값의 수이며 영상 밖 부분은 세지 않는다. sampled area는 유효 개수 × row spacing × column spacing이고, PixelOnly에서는 유효 개수 px²이다. 유효 개수가 0이면 면적은 0, 평균·SD·최소·최대는 null이다.

결과에는 원본 revision, 보정 상태, 변환 근거, 통계 알고리즘 버전, 생성 및 수정 시각을 저장한다. 원본이 달라지거나 알고리즘이 바뀌면 이전 결과를 자동으로 최신 계산값처럼 표시하지 않는다.

## 영속 데이터와 파일 재연결

프로젝트 형식은 UTF-8 JSON인 `.dview.json`을 제안한다. `schema_version` 정수, project_id, document_revision, sources, measurements, notes, layout, active_view_id, view_states를 포함한다. 초기 schema_version은 1이며 문서 버전 0.2 및 앱 v0.1과 별개다. 숫자는 유한 값만 직렬화하고 값 없음은 null과 상태로 표현한다. 이는 검토 가능한 초기 형식이며 대형 segmentation 저장 형식까지 포함하지 않는다.

`PersistentFrameRef`는 project_source_id, content SHA-256, SOP Instance UID가 있으면 그 값, 1부터 시작하는 DICOM frame number를 가진다. source locator는 sources 표에서 관리한다. project_source_id는 프로젝트 안에서 유지되는 키이며 세션의 source_id와 다르다. 저장되는 주석·메모·뷰 상태가 참조하는 모든 source는 첫 저장 완료 전에 내용 해시를 확보한다. 해시 진행도 저장 작업의 일부로 표시한다. 이미 확인된 해시가 있는 누락 source의 기존 참조는 보존할 수 있다. 저장 전 편집 모델은 임시 FrameRef를 사용할 수 있지만 미확정 해시의 영속 참조를 완성된 것으로 직렬화하지 않는다.

`PersistentViewState`는 영속 프레임 참조, 시리즈 UID와 해석한 차원 선택 조건 및 grouping 정책 버전, 표시 설정을 저장한다. display_set_id·instance_id·source_revision 같은 세션 값을 복원 키로 사용하지 않는다. 다시 열 때 원본 일치 확인 후 새 DisplaySet에 해당 프레임을 연결하며, 그룹 구성이 달라지면 재구성 사실을 표시한다. 파일 VOI의 선택 근거가 더 이상 유효하지 않으면 기본 VOI로 돌아가고 이를 알린다. 일반 메모는 프로젝트 또는 영속 프레임 참조에 연결하며, 재연결 실패로 삭제하지 않는다.

SourceLocator는 project-relative path, absolute path hint, 플랫폼 bookmark reference를 구분한다. 상대 경로의 기준은 프로젝트 파일 디렉터리다. 경로는 찾기 힌트이며 동일 파일의 증거는 아니다. 재연결 시 내용 해시와 인스턴스 정보를 확인하고, UID만 같고 내용이 다른 파일에는 주석을 자동 적용하지 않는다.

인덱스의 빠른 변경 감지는 파일 크기와 수정 시각 등 observed revision을 사용한다. 이는 내용 동일성을 보장하지 않으며 주석의 영속 연결에는 content hash 검증을 사용한다. 원본을 보존한 전송 구문 변경 파일도 바이트 해시는 달라지므로 자동 동일시하지 않는 보수적인 정책을 적용한다.

해시와 측정에 사용한 픽셀은 같은 원본 revision에서 얻어야 한다. 읽기·해시 도중 변경을 감지하면 SourceChanged로 중단하고 이전 픽셀 결과에 새 파일의 해시를 붙이지 않는다. 프로젝트를 다른 위치에 저장하면 기존에 해석된 원본 위치를 기준으로 상대 경로를 다시 계산한다. bookmark가 없거나 만료됐으면 Swift가 접근 권한을 복구한 뒤 재연결 API를 호출한다.

저장은 같은 디렉터리의 임시 파일에 완전한 문서를 쓴 뒤 교체하는 방식으로 설계하고 실패 지점을 시험한다. `SavePrecondition`은 신규 파일의 MustNotExist 또는 읽었을 때의 파일 내용 해시에 대한 MustMatch(token)이다. 기존 파일에 대한 조건 없는 덮어쓰기는 기본 API에서 허용하지 않는다. 파일 revision token은 document_revision과 구분한다. 앱 내부의 같은 대상 저장은 직렬화하고, 교체 직전 파일 조건이 달라졌으면 SaveConflict를 반환한다.

저장 receipt는 실제 기록한 document_revision을 돌려준다. 저장 중 편집으로 현재 revision이 더 커졌으면 dirty 상태를 유지한다. 교체가 확정된 뒤의 취소는 성공 결과를 취소로 바꾸지 않는다. 안전한 교체와 마지막 유효 사본 보존을 검증하되, 비협조적인 외부 편집기와의 검사·교체 사이 경쟁을 모든 파일시스템에서 원자적으로 차단한다고 약속하지 않는다. 충돌 가능 구간과 복구 사본 정책을 P4에서 시험한다. 마이그레이션은 기존 프로젝트 사본을 보존한 뒤 수행하며, 알 수 없는 미래 schema를 수정 저장하지 않는다.

CSV는 한 행에 한 측정 결과를 기록한다. measurement_id, source content hash, SOP UID가 있는 경우 그 값, DICOM frame number, measurement type, value, unit, calibration status, ROI count/mean/population SD 및 algorithm version을 포함한다. 선택한 파일 식별 정보에 따라 데이터가 개인 정보를 포함할 수 있으므로 포함 열을 UI에서 확인할 수 있게 한다. 문자열은 CSV quoting을 적용하고 스프레드시트 수식으로 해석될 수 있는 자유 텍스트를 텍스트로 내보내며 숫자 열과 구분한다.

CSV 형식은 UTF-8, 쉼표 구분, 소수점 `.`과 고정 열 순서를 기본으로 한다. ROI는 min/max, excluded_count, sampled_area 및 그 단위를 별도 열로 포함하고 해당하지 않는 값은 빈 필드로 둔다. status 열로 정상·값 없음·원본 미확인·재계산 필요를 구분한다. stale 결과는 명시적으로 선택한 경우에만 상태와 함께 내보낸다. 자유 텍스트의 따옴표 처리는 수식 실행 방지와 별개이며 대상 스프레드시트 앱에서 텍스트로 열리는지 T-17에서 검증한다.

## 계약을 검증할 시험

초기 contract test는 프레임 번호 변환, payload 길이와 endian, 변환 중복 방지, 세션 close 후 payload 수명, 취소 경합, source 변경, 저장 충돌과 schema migration을 포함한다. 상세 합격 기준은 [개발과 검증 계획](06-development-and-validation.md)의 T-06, T-10부터 T-18 및 T-21에 연결한다.
