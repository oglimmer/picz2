/* Copyright (c) 2025 by oglimmer.com / Oliver Zimpasser. All rights reserved. */
package com.oglimmer.photoupload.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.oglimmer.photoupload.config.FileStorageProperties;
import com.oglimmer.photoupload.config.JobsProperties;
import com.oglimmer.photoupload.entity.Album;
import com.oglimmer.photoupload.entity.AssetKind;
import com.oglimmer.photoupload.entity.FileMetadata;
import com.oglimmer.photoupload.entity.ProcessingStatus;
import com.oglimmer.photoupload.entity.Tag;
import com.oglimmer.photoupload.entity.User;
import com.oglimmer.photoupload.exception.ResourceNotFoundException;
import com.oglimmer.photoupload.exception.ValidationException;
import com.oglimmer.photoupload.mapper.FileInfoMapper;
import com.oglimmer.photoupload.mapper.FileInfoMapperImpl;
import com.oglimmer.photoupload.model.FileInfo;
import com.oglimmer.photoupload.repository.AlbumEnabledTagRepository;
import com.oglimmer.photoupload.repository.AlbumRepository;
import com.oglimmer.photoupload.repository.FileMetadataRepository;
import com.oglimmer.photoupload.repository.ImageTagRepository;
import com.oglimmer.photoupload.repository.SlideshowRecordingRepository;
import com.oglimmer.photoupload.repository.StorageBackendRepository;
import com.oglimmer.photoupload.repository.TagRepository;
import com.oglimmer.photoupload.security.UserContext;
import java.nio.file.Path;
import java.util.List;
import java.util.Optional;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;
import org.mockito.Mockito;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.TransactionStatus;

/**
 * Text cards (D86): an album entry that carries a chapter heading instead of pixels.
 *
 * <p>The load-bearing assertion is the mime type. Every sweep, cover picker and rewrite gate in the
 * codebase narrows on {@code image/%} or {@code video/%}, so a card is skipped by all of them only
 * as long as its type sits outside both families — and {@code kind} on the wire is derived from
 * that same type rather than stored beside it.
 */
class FileStorageServiceTextCardTest {

  private static final long USER_ID = 1L;
  private static final long ALBUM_ID = 7L;
  private static final long CARD_ID = 100L;
  private static final long PHOTO_ID = 101L;
  private static final long NEW_ASSET_TAG_ID = 55L;

  private FileMetadataRepository metaRepo;
  private ImageTagRepository imageTagRepo;
  private JobEnqueueService jobs;
  private SystemTagProvisioner tagProvisioner;
  private FileStorageService svc;

  private User user;
  private Album album;
  private FileMetadata card;
  private FileMetadata photo;

  @BeforeEach
  void setUp(@TempDir Path tempDir) {
    FileStorageProperties props = new FileStorageProperties();
    props.setUploadDir(tempDir.toString());

    metaRepo = Mockito.mock(FileMetadataRepository.class);
    imageTagRepo = Mockito.mock(ImageTagRepository.class);
    jobs = Mockito.mock(JobEnqueueService.class);
    tagProvisioner = Mockito.mock(SystemTagProvisioner.class);
    TagRepository tagRepo = Mockito.mock(TagRepository.class);
    AlbumRepository albumRepo = Mockito.mock(AlbumRepository.class);
    UserContext userContext = Mockito.mock(UserContext.class);
    PlatformTransactionManager txManager = Mockito.mock(PlatformTransactionManager.class);
    when(txManager.getTransaction(any())).thenReturn(Mockito.mock(TransactionStatus.class));

    user = new User();
    user.setId(USER_ID);
    user.setEmail("owner@example.com");
    user.setNewAssetTag("hidden");

    album = new Album();
    album.setId(ALBUM_ID);
    album.setUser(user);

    card = new FileMetadata();
    card.setId(CARD_ID);
    card.setAlbum(album);
    card.setStoredFilename("text-card-abc");
    card.setMimeType(AssetKind.TEXT_CARD_MIME_TYPE);
    card.setHeadline("Day one");

    photo = new FileMetadata();
    photo.setId(PHOTO_ID);
    photo.setAlbum(album);
    photo.setStoredFilename("photo.jpg");
    photo.setMimeType("image/jpeg");

    when(userContext.getCurrentUser()).thenReturn(user);
    when(albumRepo.findByUserAndId(user, ALBUM_ID)).thenReturn(Optional.of(album));
    when(metaRepo.findByIdAndUserId(CARD_ID, USER_ID)).thenReturn(Optional.of(card));
    when(metaRepo.findByIdAndUserId(PHOTO_ID, USER_ID)).thenReturn(Optional.of(photo));
    when(metaRepo.save(any(FileMetadata.class))).thenAnswer(i -> i.getArgument(0));
    when(metaRepo.findMaxDisplayOrderByAlbumIdAndUserId(ALBUM_ID, USER_ID)).thenReturn(4);
    when(imageTagRepo.findByFileMetadataId(anyLong())).thenReturn(List.of());
    when(imageTagRepo.findByFileMetadataIdAndTagId(anyLong(), anyLong()))
        .thenReturn(Optional.empty());
    when(tagProvisioner.ensureTag(user, "hidden")).thenReturn(NEW_ASSET_TAG_ID);
    when(tagRepo.getReferenceById(NEW_ASSET_TAG_ID)).thenReturn(new Tag());

    // The real mapper, not a stub: `kind` is derived inside it, and a test against a stub would
    // pass while the derivation was broken.
    FileInfoMapper mapper = new FileInfoMapperImpl();

    svc =
        new FileStorageService(
            props,
            metaRepo,
            tagRepo,
            imageTagRepo,
            Mockito.mock(AlbumEnabledTagRepository.class),
            Mockito.mock(JdbcTemplate.class),
            albumRepo,
            Mockito.mock(SlideshowRecordingRepository.class),
            Mockito.mock(StorageBackendRepository.class),
            mapper,
            userContext,
            txManager,
            jobs,
            tagProvisioner,
            Mockito.mock(StorageQuotaService.class),
            Mockito.mock(ObjectStorageService.class),
            Mockito.mock(JobQueueDepthService.class),
            new JobsProperties());
  }

  // --- create ---------------------------------------------------------------------------------

  @Test
  void createStoresARowThatOwnsNoBytesAndNeedsNoProcessing() {
    FileInfo created = svc.createTextCard(ALBUM_ID, "  Day one  ", "  We flew in at dawn.  ");

    FileMetadata saved = savedRow();
    // The mime type is the mechanism, not a label: it is what keeps this row out of the
    // thumbnail, transcode, EXIF, GPS and cover-picker paths.
    assertThat(saved.getMimeType()).isEqualTo(AssetKind.TEXT_CARD_MIME_TYPE);
    assertThat(saved.getFilePath()).isNull();
    assertThat(saved.getFileSize()).isZero();
    // DONE from birth. Left at QUEUED, both clients would spin on a job that does not exist.
    assertThat(saved.getProcessingStatus()).isEqualTo(ProcessingStatus.DONE);
    assertThat(saved.getProcessingCompletedAt()).isNotNull();
    assertThat(saved.getHeadline()).isEqualTo("Day one");
    assertThat(saved.getBodyText()).isEqualTo("We flew in at dawn.");
    // The headline doubles as the row's name, because that is what every list prints.
    assertThat(saved.getOriginalName()).isEqualTo("Day one");

    assertThat(created.getKind()).isEqualTo(AssetKind.TEXT_CARD);
    assertThat(created.getHeadline()).isEqualTo("Day one");
    assertThat(created.getBodyText()).isEqualTo("We flew in at dawn.");
  }

  @Test
  void createLandsAtTheEndOfTheAlbumsOrder() {
    svc.createTextCard(ALBUM_ID, "Day one", null);

    assertThat(savedRow().getDisplayOrder()).isEqualTo(5);
  }

  @Test
  void createEnqueuesNoJob() {
    svc.createTextCard(ALBUM_ID, "Day one", null);

    Mockito.verifyNoInteractions(jobs);
  }

  /**
   * D79 has to stay true for every row, not only for photos: a card with no tag at all would read
   * as {@code hidden} anyway, so it gets the user's new-asset tag exactly like an upload.
   */
  @Test
  void createGivesTheCardTheUsersNewAssetTag() {
    svc.createTextCard(ALBUM_ID, "Day one", null);

    verify(tagProvisioner).ensureTag(user, "hidden");
    verify(imageTagRepo).save(any());
  }

  @Test
  void createStoresABareHeadingWhenThereIsNoBody() {
    svc.createTextCard(ALBUM_ID, "Day one", "   ");

    assertThat(savedRow().getBodyText()).isNull();
  }

  @Test
  void createRefusesABlankHeadline() {
    assertThatThrownBy(() -> svc.createTextCard(ALBUM_ID, "   ", "body"))
        .isInstanceOf(ValidationException.class);
    verify(metaRepo, never()).save(any());
  }

  @Test
  void createRefusesAHeadlineLongerThanTheColumn() {
    assertThatThrownBy(() -> svc.createTextCard(ALBUM_ID, "x".repeat(201), null))
        .isInstanceOf(ValidationException.class);
    verify(metaRepo, never()).save(any());
  }

  @Test
  void createRefusesABodyLongerThanTheCap() {
    assertThatThrownBy(() -> svc.createTextCard(ALBUM_ID, "Day one", "x".repeat(4001)))
        .isInstanceOf(ValidationException.class);
    verify(metaRepo, never()).save(any());
  }

  @Test
  void createRefusesAMissingAlbum() {
    assertThatThrownBy(() -> svc.createTextCard(null, "Day one", null))
        .isInstanceOf(ValidationException.class);
  }

  @Test
  void createRefusesAnAlbumThatIsNotTheCallersOwn() {
    assertThatThrownBy(() -> svc.createTextCard(999L, "Day one", null))
        .isInstanceOf(ResourceNotFoundException.class);
    verify(metaRepo, never()).save(any());
  }

  // --- update ---------------------------------------------------------------------------------

  @Test
  void updateRewritesTheHeadingAndTheBody() {
    card.setBodyText("Older text");

    FileInfo updated = svc.updateTextCard(CARD_ID, "  Day two  ", "  Over the pass.  ");

    assertThat(card.getHeadline()).isEqualTo("Day two");
    assertThat(card.getOriginalName()).isEqualTo("Day two");
    assertThat(card.getBodyText()).isEqualTo("Over the pass.");
    assertThat(updated.getHeadline()).isEqualTo("Day two");
    assertThat(updated.getKind()).isEqualTo(AssetKind.TEXT_CARD);
    verify(metaRepo).save(card);
  }

  @Test
  void updateWithABlankBodyClearsIt() {
    card.setBodyText("Older text");

    svc.updateTextCard(CARD_ID, "Day two", "  ");

    assertThat(card.getBodyText()).isNull();
  }

  @Test
  void updateRefusesABlankHeadline() {
    assertThatThrownBy(() -> svc.updateTextCard(CARD_ID, " ", "body"))
        .isInstanceOf(ValidationException.class);
    verify(metaRepo, never()).save(any());
  }

  /** A photo has no headline. Accepting one would leave a row that lies about what it is. */
  @Test
  void updateRefusesAPhoto() {
    assertThatThrownBy(() -> svc.updateTextCard(PHOTO_ID, "Day two", null))
        .isInstanceOf(ValidationException.class);
    verify(metaRepo, never()).save(any());
  }

  @Test
  void updateRefusesARowThatIsNotTheCallersOwn() {
    when(metaRepo.findByIdAndUserId(999L, USER_ID)).thenReturn(Optional.empty());

    assertThatThrownBy(() -> svc.updateTextCard(999L, "Day two", null))
        .isInstanceOf(ResourceNotFoundException.class);
  }

  // --- kind is derived, never stored ----------------------------------------------------------

  @Test
  void kindFollowsTheMimeTypeForEveryFamily() {
    assertThat(AssetKind.ofMimeType(AssetKind.TEXT_CARD_MIME_TYPE)).isEqualTo(AssetKind.TEXT_CARD);
    assertThat(AssetKind.ofMimeType("image/jpeg")).isEqualTo(AssetKind.PHOTO);
    assertThat(AssetKind.ofMimeType("video/mp4")).isEqualTo(AssetKind.PHOTO);
    // A row whose type was never recorded is a photo, not a card: the fallback must never invent
    // a card, because a card is drawn as text and would swallow a real picture.
    assertThat(AssetKind.ofMimeType(null)).isEqualTo(AssetKind.PHOTO);
  }

  private FileMetadata savedRow() {
    org.mockito.ArgumentCaptor<FileMetadata> captor =
        org.mockito.ArgumentCaptor.forClass(FileMetadata.class);
    verify(metaRepo).save(captor.capture());
    return captor.getValue();
  }
}
