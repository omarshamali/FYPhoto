//
//  PhotoDetailCollectionViewController.swift
//  FYPhotoPicker
//
//  Created by xiaoyang on 2020/7/27.
//

import UIKit
import Photos
import MobileCoreServices

private let photoCellReuseIdentifier = "PhotoDetailCell"
private let videoCellReuseIdentifier = "VideoDetailCell"

public class PhotoDetailCollectionViewController: UIViewController, UICollectionViewDataSource, UICollectionViewDelegate {

    public weak var delegate: PhotoDetailCollectionViewControllerDelegate?

    var selectedPhotos: [PhotoProtocol] = [] {
        willSet {
            let assetIdentifiers = newValue.compactMap { $0.asset?.localIdentifier }
            delegate?.photoDetail(self, selectedAssets: assetIdentifiers)
        }
    }

    /// the maximum number of photos you can select
    var maximumNumber: Int = 0

    // bar item
    fileprivate var doneBarItem: UIBarButtonItem!
    fileprivate var addPhotoBarItem: UIBarButtonItem!
    fileprivate var playVideoBarItem: UIBarButtonItem!
    fileprivate var pauseVideoBarItem: UIBarButtonItem!

    fileprivate let photos: [PhotoProtocol]

    fileprivate let imageManager = PHCachingImageManager()

    fileprivate let collectionView: UICollectionView

    fileprivate let captionView = CaptionView()

    fileprivate var playBarItemsIsShowed = false

    fileprivate var initialScrollDone = false

    fileprivate let addLocalizedString = "add".photoTablelocalized

    fileprivate var previousNavigationBarHidden: Bool?
    fileprivate var previousToolBarHidden: Bool?
    fileprivate var previousInteractivePop: Bool?
    fileprivate var previousNavigationTitle: String?
    fileprivate var previousAudioCategory: AVAudioSession.Category?

    fileprivate var originCaptionTransform: CGAffineTransform!

    fileprivate var flowLayout: UICollectionViewFlowLayout? {
        return collectionView.collectionViewLayout as? UICollectionViewFlowLayout
    }

    fileprivate var assetSize: CGSize?

    fileprivate var resized = false

    // MARK: Video properties
    var player: AVPlayer?
    var playerItem: AVPlayerItem?
    var isPlaying = false {
        willSet {
            if currentPhoto.isVideo {
                updateToolBarItems(isPlaying: newValue)
            }
        }
    }
    let assetKeys = [
        "playable",
        "hasProtectedContent"
    ]
    // Key-value observing context
    private var playerItemStatusContext = 0
    /// After the movie has played to its end time, seek back to time zero
    /// to play it again.
    private var seekToZeroBeforePlay: Bool = false

    fileprivate var currentDisplayedIndexPath: IndexPath {
        willSet {
            stopPlayingIfNeeded()
            currentPhoto = photos[newValue.item]
            if currentDisplayedIndexPath != newValue {
                delegate?.photoDetail(self, scrollAt: newValue)
            }
            if let canSelect = delegate?.canSelectPhoto(in: self), canSelect {
                updateAddBarItem(at: newValue)
            }
            if let canDisplay = delegate?.canDisplayCaption(in: self), canDisplay {
                updateCaption(at: newValue)
            }
            updateNavigationTitle(at: newValue)
            stopPlayingVideoIfNeeded(at: currentDisplayedIndexPath)
        }
    }

    fileprivate var currentPhoto: PhotoProtocol {
        willSet {
            var showDone = false
            if let canSelect = delegate?.canSelectPhoto(in: self), canSelect {
                showDone = canSelect
            }
            if newValue.isVideo {
                // tool bar items
                if !playBarItemsIsShowed {
                    updateToolBar(shouldShowDone: showDone, shouldShowPlay: true)
                    playBarItemsIsShowed = true
                } else {
                    updateToolBarItems(isPlaying: isPlaying)
                }
            } else {
                updateToolBar(shouldShowDone: showDone, shouldShowPlay: false)
                playBarItemsIsShowed = false
            }
        }
    }


    // MARK: - LifeCycle
    public init(photos: [PhotoProtocol], initialIndex: Int) {
        self.photos = photos
        self.currentDisplayedIndexPath = IndexPath(row: initialIndex, section: 0)
        self.currentPhoto = photos[currentDisplayedIndexPath.item]
        let flowLayout = UICollectionViewFlowLayout()
        flowLayout.minimumInteritemSpacing = 0
        flowLayout.minimumLineSpacing = 20
        flowLayout.sectionInset = UIEdgeInsets(top: 0, left: 10, bottom: 0, right: 10)
        flowLayout.scrollDirection = .horizontal
//        flowLayout.itemSize = frame.size
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: flowLayout)
        super.init(nibName: nil, bundle: nil)
    }

    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        print(#file, #function, "☠️☠️☠️☠️☠️☠️")
        NotificationCenter.default.removeObserver(self)
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        view.clipsToBounds = true
        view.backgroundColor = UIColor.white
        edgesForExtendedLayout = .all

        previousToolBarHidden = self.navigationController?.toolbar.isHidden
        previousNavigationBarHidden = self.navigationController?.navigationBar.isHidden
        previousInteractivePop = self.navigationController?.interactivePopGestureRecognizer?.isEnabled
        previousNavigationTitle = self.navigationController?.navigationItem.title
        previousAudioCategory = AVAudioSession.sharedInstance().category

        view.addSubview(collectionView)
        view.addSubview(captionView)

        setupCollectionView()

        setupNavigationBar()
        setupNavigationToolBar()
        // Uncomment the following line to preserve selection between presentations
        // self.clearsSelectionOnViewWillAppear = false
        makeConstraints()
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        try? AVAudioSession.sharedInstance().setCategory(.playback)
        self.navigationController?.interactivePopGestureRecognizer?.isEnabled = false
        if let showNavigationBar = delegate?.showNavigationBar(in: self) {
            self.navigationController?.setNavigationBarHidden(!showNavigationBar, animated: true)
        } else {
            self.navigationController?.setNavigationBarHidden(true, animated: false)
        }

        if let showToolBar = delegate?.showBottomToolBar(in: self) {
            self.navigationController?.setToolbarHidden(!showToolBar, animated: false)
        } else {
            self.navigationController?.setToolbarHidden(true, animated: false)
        }

        originCaptionTransform = captionView.transform
    }

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        print(collectionView.contentOffset)
    }
    
    public override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stopPlayingIfNeeded()
        restoreNavigationControllerData()
    }

    func setupCollectionView() {
        collectionView.register(PhotoDetailCell.self, forCellWithReuseIdentifier: photoCellReuseIdentifier)
        collectionView.register(VideoDetailCell.self, forCellWithReuseIdentifier: videoCellReuseIdentifier)
        collectionView.isPagingEnabled = true
        collectionView.delegate = self
        collectionView.dataSource = self
//        collectionView.backgroundColor = .white
        collectionView.contentInsetAdjustmentBehavior = .never
    }

    func setupNavigationBar() {
        self.navigationController?.navigationBar.tintColor = .white
        self.navigationController?.navigationBar.topItem?.backBarButtonItem = UIBarButtonItem(title: "", style: .plain, target: nil, action: nil)
        if let canSelect = delegate?.canSelectPhoto(in: self), canSelect {
            addPhotoBarItem = UIBarButtonItem(title: "", style: .plain, target: self, action: #selector(PhotoDetailCollectionViewController.addPhotoBarItemClicked(_:)))
            addPhotoBarItem.title = addLocalizedString
            addPhotoBarItem.tintColor = .black
            self.navigationItem.rightBarButtonItem = addPhotoBarItem
        }
        updateNavigationTitle(at: currentDisplayedIndexPath)
    }

    func setupNavigationToolBar() {
        if let showToolBar = delegate?.showBottomToolBar(in: self), showToolBar {
            playVideoBarItem = UIBarButtonItem(barButtonSystemItem: UIBarButtonItem.SystemItem.play, target: self, action: #selector(PhotoDetailCollectionViewController.playVideoBarItemClicked(_:)))
            pauseVideoBarItem = UIBarButtonItem(barButtonSystemItem: UIBarButtonItem.SystemItem.pause, target: self, action: #selector(PhotoDetailCollectionViewController.playVideoBarItemClicked(_:)))

            var showVideoPlay = false
            if currentPhoto.isVideo {
                showVideoPlay = true
            }
            var showDone = false

            if let canSelect = delegate?.canSelectPhoto(in: self), canSelect {
                doneBarItem = UIBarButtonItem(barButtonSystemItem: UIBarButtonItem.SystemItem.done, target: self, action: #selector(PhotoDetailCollectionViewController.doneBarButtonClicked(_:)))
                doneBarItem.isEnabled = !selectedPhotos.isEmpty
                showDone = canSelect
            }

            updateToolBar(shouldShowDone: showDone, shouldShowPlay: showVideoPlay)
        }
    }

    fileprivate func restoreNavigationControllerData() {
        if let title = previousNavigationTitle {
            navigationItem.title = title
        }

        self.navigationController?.interactivePopGestureRecognizer?.isEnabled = previousInteractivePop ?? true

        if let originalIsNavigationBarHidden = previousNavigationBarHidden {
            navigationController?.setNavigationBarHidden(originalIsNavigationBarHidden, animated: false)
        }
        // Drag to dismiss quickly canceled, may result in a navigation hide animation bug
        if let originalToolBarHidden = previousToolBarHidden {
            //            navigationController?.setToolbarHidden(originalToolBarHidden, animated: false)
            navigationController?.isToolbarHidden = originalToolBarHidden
        }

        if let audioCategory = previousAudioCategory {
            try? AVAudioSession.sharedInstance().setCategory(audioCategory)
        }
    }

    func makeConstraints() {
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: self.view.topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: self.view.bottomAnchor),
            collectionView.trailingAnchor.constraint(equalTo: self.view.trailingAnchor)
        ])

        captionView.translatesAutoresizingMaskIntoConstraints = false
        if #available(iOS 11.0, *) {
            NSLayoutConstraint.activate([
                captionView.leadingAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.leadingAnchor, constant: 10),
                captionView.bottomAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.bottomAnchor, constant: -10),
                captionView.trailingAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.trailingAnchor, constant: -10),
            ])
        } else {
            NSLayoutConstraint.activate([
                captionView.leadingAnchor.constraint(equalTo: self.view.leadingAnchor, constant: 10),
                captionView.bottomAnchor.constraint(equalTo: self.view.bottomAnchor, constant: -10),
                captionView.trailingAnchor.constraint(equalTo: self.view.trailingAnchor, constant: -10),
            ])
        }
    }

    func hideCaptionView(_ flag: Bool, animated: Bool = true) {
        if flag { // hide
            let transition = CGAffineTransform(translationX: 0, y: captionView.bounds.height)
            if animated {
                UIView.animate(withDuration: 0.2, animations: {
                    self.captionView.transform = transition
                }) { (_) in
                    self.captionView.isHidden = true
                }
            } else {
                captionView.transform = transition
                captionView.isHidden = true
            }
        } else { // show
            captionView.isHidden = false
            if animated {
                UIView.animate(withDuration: 0.3) {
                    self.captionView.transform = self.originCaptionTransform
                }
            } else {
                self.captionView.transform = originCaptionTransform
            }
        }
    }
    // MARK: UICollectionViewDataSource

    public func numberOfSections(in collectionView: UICollectionView) -> Int {
        // #warning Incomplete implementation, return the number of sections
        return 1
    }


    public func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        // #warning Incomplete implementation, return the number of items
        return photos.count
    }

    public func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let photo = photos[indexPath.row]
        if photo.isVideo {
            if let cell = collectionView.dequeueReusableCell(withReuseIdentifier: videoCellReuseIdentifier, for: indexPath) as? VideoDetailCell {                
                return cell
            }
        } else {
            if let cell = collectionView.dequeueReusableCell(withReuseIdentifier: photoCellReuseIdentifier, for: indexPath) as? PhotoDetailCell {
                cell.maximumZoomScale = 2
                return cell
            }
        }

        return UICollectionViewCell()
    }

    public func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        stopPlayingVideoIfNeeded(at: currentDisplayedIndexPath)

        var photo = photos[indexPath.row]
        photo.assetSize = assetSize
        if photo.isVideo {
            if let videoCell = cell as? VideoDetailCell {
                videoCell.photo = photo
                // setup video player
                setupPlayer(photo: photo, for: videoCell.playerView)
            }
        } else {
            if let photoCell = cell as? PhotoDetailCell {
                photoCell.setPhoto(photo)
            }
        }
    }

    public override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        // Device rotating
        // Instruct collection view how to handle changes in page size

        recalculateItemSize(inBoundingSize: size)
        if view.window == nil {
            view.frame = CGRect(origin: view.frame.origin, size: size)
            view.layoutIfNeeded()
        } else {
            let indexPath = self.collectionView.indexPathsForVisibleItems.last
            coordinator.animate(alongsideTransition: { ctx in
                self.collectionView.layoutIfNeeded()
                if let indexPath = indexPath {
                    self.collectionView.scrollToItem(at: indexPath, at: .centeredHorizontally, animated: false)
                }
            }, completion: { _ in

            })
        }

        super.viewWillTransition(to: size, with: coordinator)
    }

    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if self.collectionView.frame != view.frame.insetBy(dx: -10.0, dy: 0.0) {
            self.collectionView.frame = view.frame.insetBy(dx: -10.0, dy: 0.0)
        }
        if !resized && view.bounds.size != .zero {
            resized = true
            recalculateItemSize(inBoundingSize: view.bounds.size)
        }

        if (!self.initialScrollDone) {
            self.initialScrollDone = true
            self.collectionView.scrollToItem(at: currentDisplayedIndexPath, at: .centeredHorizontally, animated: false)
            if let canSelect = delegate?.canSelectPhoto(in: self), canSelect {
                updateAddBarItem(at: currentDisplayedIndexPath)
            }
            if let canDisplay = delegate?.canDisplayCaption(in: self), canDisplay {
                updateCaption(at: currentDisplayedIndexPath)
            }
        }
    }

    // MARK: -Bar item actions
    @objc func doneBarButtonClicked(_ sender: UIBarButtonItem) {
        assert(!selectedPhotos.isEmpty, "photos shouldn't be empty")
        delegate?.photoDetail(self, didCompleteSelected: selectedPhotos)
    }

    @objc func addPhotoBarItemClicked(_ sender: UIBarButtonItem) {
        defer {
            doneBarItem.isEnabled = !selectedPhotos.isEmpty
        }

        let photo = photos[currentDisplayedIndexPath.row]

        // already added, remove it from selections
        if let exsit = firstIndexOfPhoto(photo, in: selectedPhotos) {
            selectedPhotos.remove(at: exsit)
            addPhotoBarItem.title = addLocalizedString
            addPhotoBarItem.tintColor = .black
            return
        }

        // add photo
        selectedPhotos.append(photo)

        // update bar item: add, done
        if let firstIndex = firstIndexOfPhoto(photo, in: selectedPhotos) {
            addPhotoBarItem.title = "\(firstIndex + 1)"
            addPhotoBarItem.tintColor = .systemBlue
        }

        // filter different media type
    }

    @objc func playVideoBarItemClicked(_ sender: UIBarButtonItem) {
        guard currentPhoto.isVideo else { return }
        if isPlaying {
            pausePlayback()
        } else {
            playVideo()
        }
    }

    // MARK: ToolBar updates
    func updateToolBar(shouldShowDone: Bool, shouldShowPlay: Bool) {
        var items = [UIBarButtonItem]()
        let spaceItem = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: self, action: nil)
        if shouldShowPlay {
            items.append(spaceItem)
            items.append(playVideoBarItem)
            items.append(spaceItem)
        } else {
            items.append(spaceItem)
        }

        if shouldShowDone {
            items.append(doneBarItem)
        }
        self.setToolbarItems(items, animated: true)
    }

    func updateToolBarItems(isPlaying: Bool) {
        var toolbarItems = self.toolbarItems
        if isPlaying {
            if let index = toolbarItems?.firstIndex(of: playVideoBarItem) {
                toolbarItems?.remove(at: index)
                toolbarItems?.insert(pauseVideoBarItem, at: index)
            }
        } else {
            if let index = toolbarItems?.firstIndex(of: pauseVideoBarItem) {
                toolbarItems?.remove(at: index)
                toolbarItems?.insert(playVideoBarItem, at: index)
            }
        }
        self.setToolbarItems(toolbarItems, animated: true)
    }

    func updateAddBarItem(at indexPath: IndexPath) {
        let photo = photos[indexPath.row]
        guard let firstIndex = firstIndexOfPhoto(photo, in: selectedPhotos) else {
            addPhotoBarItem.title = addLocalizedString
            addPhotoBarItem.isEnabled = selectedPhotos.count < maximumNumber
            addPhotoBarItem.tintColor = .black
            return
        }
        addPhotoBarItem.isEnabled = true
        addPhotoBarItem.title = "\(firstIndex + 1)"
        addPhotoBarItem.tintColor = .systemBlue
    }

    func stopPlayingVideoIfNeeded(at oldIndexPath: IndexPath) {
        if isPlaying {
            stopPlayingIfNeeded()
        }
    }

    func updateCaption(at indexPath: IndexPath) {
        let photo = photos[indexPath.row]
        captionView.setup(content: photo.captionContent, signature: photo.captionSignature)
    }

    func updateNavigationTitle(at indexPath: IndexPath) {
        if let showNavigationBar = delegate?.showNavigationBar(in: self), showNavigationBar {
            if let canSelect = delegate?.canSelectPhoto(in: self), canSelect {
                navigationItem.title = ""
            } else {
                navigationItem.title = "\(indexPath.item + 1) /\(photos.count)"
            }
        }
    }

    @objc func playerItemDidReachEnd(_ notification: Notification) {
        isPlaying = false
        seekToZeroBeforePlay = true
    }

    func recalculateItemSize(inBoundingSize size: CGSize) {
        guard let flowLayout = flowLayout else { return }
        let itemSize = recalculateLayout(flowLayout,
                                         inBoundingSize: size)
        let scale = UIScreen.main.scale
        assetSize = CGSize(width: itemSize.width * scale, height: itemSize.height * scale)
    }

    @discardableResult
    func recalculateLayout(_ layout: UICollectionViewFlowLayout, inBoundingSize size: CGSize) -> CGSize {
        layout.minimumInteritemSpacing = 0
        layout.sectionInset = UIEdgeInsets(top: 0, left: 10, bottom: 0, right: 10)
        layout.scrollDirection = .horizontal;
        layout.minimumLineSpacing = 20
        layout.itemSize = size
        return size
    }

    public override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        stopPlayingIfNeeded()
        player = nil
    }
}

extension PhotoDetailCollectionViewController: UIScrollViewDelegate {
    public func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
//        let pageWidth = view.bounds.size.width
//        let currentPage = Int((scrollView.contentOffset.x + pageWidth / 2) / pageWidth)
        if let currentIndexPath = self.collectionView.indexPathsForVisibleItems.last {
            currentDisplayedIndexPath = currentIndexPath
        } else {
            currentDisplayedIndexPath = IndexPath(row: 0, section: 0)
        }

    }
}

// MARK: - Router event
extension PhotoDetailCollectionViewController {
    override func routerEvent(name: String, userInfo: [AnyHashable : Any]?) {
        if let tap = ImageViewTap(rawValue: name) {
            switch tap {
            case .singleTap:
                hideOrShowTopBottom()
            case .doubleTap:
                if let userInfo = userInfo, let mediaType = userInfo["mediaType"] as? String {
                    let cfstring = mediaType as CFString
                    switch cfstring {
                    case kUTTypeImage:
                        if let touchPoint = userInfo["touchPoint"] as? CGPoint,
                           let cell = collectionView.cellForItem(at: currentDisplayedIndexPath) as? PhotoDetailCell  {
                            handleDoubleTap(touchPoint, on: cell)
                        }
                    case kUTTypeVideo:
                        if isPlaying {
                            pausePlayback()
                        } else {
                            playVideo()
                        }
                    default: break

                    }
                }
            }
        } else {
            // pass the event
            next?.routerEvent(name: name, userInfo: userInfo)
        }
    }
    func hideOrShowTopBottom() {
        if let showNavigationBar = delegate?.showNavigationBar(in: self), showNavigationBar {
            self.navigationController?.setNavigationBarHidden(!(self.navigationController?.isNavigationBarHidden ?? true), animated: true)
        }

        if let showToolBar = delegate?.showBottomToolBar(in: self), showToolBar {
            self.navigationController?.setToolbarHidden(!(self.navigationController?.isToolbarHidden ?? true), animated: true)
        }

        if let canDisplay = delegate?.canDisplayCaption(in: self), canDisplay {
            hideCaptionView(!captionView.isHidden)
        }
    }

    func handleDoubleTap(_ touchPoint: CGPoint, on cell: PhotoDetailCell) {
        let scale = min(cell.zoomingView.zoomScale * 2, cell.zoomingView.maximumZoomScale)
        if cell.zoomingView.zoomScale == 1 {
            let zoomRect = zoomRectForScale(scale: scale, center: touchPoint, for: cell.zoomingView)
            cell.zoomingView.zoom(to: zoomRect, animated: true)
        } else {
            cell.zoomingView.setZoomScale(1, animated: true)
        }
    }

    func zoomRectForScale(scale: CGFloat, center: CGPoint, for scroolView: UIScrollView) -> CGRect {
        var zoomRect = CGRect.zero
        zoomRect.size.height = scroolView.frame.size.height / scale
        zoomRect.size.width  = scroolView.frame.size.width  / scale

        zoomRect.origin.x = center.x - (zoomRect.size.width / 2.0)
        zoomRect.origin.y = center.y - (zoomRect.size.height / 2.0)
        return zoomRect
    }
}

// MARK: - Video
extension PhotoDetailCollectionViewController {
    fileprivate var currentVideoCell: VideoDetailCell? {
        return collectionView.cellForItem(at: currentDisplayedIndexPath) as? VideoDetailCell
    }

    fileprivate func setupPlayer(photo: PhotoProtocol, for playerView: PlayerView) {
        if let asset = photo.asset {
            setupPlayer(asset: asset, for: playerView)
        } else if let url = photo.url {
            setupPlayer(url: url, for: playerView)
        }
    }

    fileprivate func setupPlayer(asset: PHAsset, for playerView: PlayerView) {
        let options = PHVideoRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        options.progressHandler = { progress, error, stop, info in
            print("request video from icloud progress: \(progress)")
        }
        PHImageManager.default().requestPlayerItem(forVideo: asset, options: options) { (item, info) in
            if let item = item {
                let player = self.preparePlayer(with: item)
                playerView.player = player
                self.player = player
                self.playerItem = item
            }
        }
    }

    fileprivate func setupPlayer(url: URL, for playerView: PlayerView) {
        if url.isFileURL {
            // Create asset to be played
            let asset = AVAsset(url: url)
            // Create a new AVPlayerItem with the asset and an
            // array of asset keys to be automatically loaded
            let playerItem = AVPlayerItem(asset: asset, automaticallyLoadedAssetKeys: assetKeys)
            let player = preparePlayer(with: playerItem)
            playerView.player = player
            self.player = player
        } else {
            VideoCache.fetchURL(key: url) { (filePath) in
                // Create a new AVPlayerItem with the asset and an
                // array of asset keys to be automatically loaded
                let asset = AVAsset(url: filePath)
                let playerItem = AVPlayerItem(asset: asset, automaticallyLoadedAssetKeys: self.assetKeys)
                let player = self.preparePlayer(with: playerItem)
                playerView.player = player
                self.player = player
            } failed: { (error) in
                print("FYPhoto fetch url error: \(error)")
            }
        }
    }

    func preparePlayer(with playerItem: AVPlayerItem) -> AVPlayer {
        // Register as an observer of the player item's status property
//        playerItem.addObserver(self,
//                               forKeyPath: #keyPath(AVPlayerItem.status),
//                               options: [.old, .new],
//                               context: &playerItemStatusContext)
        NotificationCenter.default.addObserver(self, selector: #selector(playerItemDidReachEnd(_:)), name: NSNotification.Name.AVPlayerItemDidPlayToEndTime, object: playerItem)

//        playerItem.addObserver(self, forKeyPath: "status", options: [.initial, .new], context: nil)

        seekToZeroBeforePlay = false
        // Associate the player item with the player

        if let player = self.player {
            player.pause()
            player.replaceCurrentItem(with: playerItem)
            return player
        } else {
            return AVPlayer(playerItem: playerItem)
        }
    }

    func playVideo() {
        guard let player = player else { return }
        if seekToZeroBeforePlay {
            seekToZeroBeforePlay = false
            player.seek(to: .zero)
        }

        player.play()
        isPlaying = true
    }

    func pausePlayback() {
        player?.pause()
        isPlaying = false
    }

    func stopPlayingIfNeeded() {
        guard let player = player, isPlaying else {
            return
        }
        player.pause()
        player.seek(to: .zero)
        isPlaying = false
    }

    public override class func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        if keyPath == "status" {
            if let status = change?[.newKey] as? AVPlayerItem.Status {
                switch status {
                case .readyToPlay:
                    print("ready to play")
                case .failed:
                    print("Faild to play")
                case .unknown:
                    break
                }
            }
        }
        super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
    }
}

// MARK: - PhotoDetailTransitionAnimatorDelegate
extension PhotoDetailCollectionViewController: PhotoTransitioning {
    public func transitionWillStart() {
        guard let cell = collectionView.cellForItem(at: currentDisplayedIndexPath) else { return }
        cell.isHidden = true
    }

    public func transitionDidEnd() {
        guard let cell = collectionView.cellForItem(at: currentDisplayedIndexPath) else { return }
        cell.isHidden = false
    }

    public func referenceImage() -> UIImage? {
        if let cell = collectionView.cellForItem(at: currentDisplayedIndexPath) as? PhotoDetailCell {
            return cell.image
        }
        if let cell = collectionView.cellForItem(at: currentDisplayedIndexPath) as? VideoDetailCell {
            return cell.image
        }
        return nil
    }

    public func imageFrame() -> CGRect? {
        if let cell = collectionView.cellForItem(at: currentDisplayedIndexPath) as? PhotoDetailCell {
            return CGRect.makeRect(aspectRatio: cell.image?.size ?? .zero, insideRect: cell.bounds)
        }
        if let cell = collectionView.cellForItem(at: currentDisplayedIndexPath) as? VideoDetailCell {
            return CGRect.makeRect(aspectRatio: cell.image?.size ?? .zero, insideRect: cell.bounds)
        }
        return nil
    }
}

extension PhotoDetailCollectionViewController {
    func firstIndexOfPhoto(_ photo: PhotoProtocol, in photos: [PhotoProtocol]) -> Int? {
        if let equals = selectedPhotos as? [Photo], let photo = photo as? Photo {
            let index = equals.firstIndex(of: photo)
            return index
        } else {
            let index = selectedPhotos.firstIndex { (photoPro) -> Bool in
                if let proAsset = photoPro.asset, let photoAsset = photo.asset {
                    return proAsset.localIdentifier == photoAsset.localIdentifier
                }
                if let proURL = photoPro.url, let photoURL = photo.url {
                    return proURL == photoURL
                }
                return photo.underlyingImage == photoPro.underlyingImage
            }
            return index
        }
    }
}
