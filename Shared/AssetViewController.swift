/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Implements the view controller that displays a single asset.
*/

import UIKit
import Photos
import PhotosUI

// MARK - 画像ファイル詳細画面
class AssetViewController: UIViewController {
    
    var asset: PHAsset!
    var assetCollection: PHAssetCollection!
    
    @IBOutlet weak var imageView: UIImageView!
    @IBOutlet weak var livePhotoView: PHLivePhotoView!
    @IBOutlet weak var editButton: UIBarButtonItem!
    @IBOutlet weak var progressView: UIProgressView!
    
    #if os(tvOS)
    @IBOutlet var livePhotoPlayButton: UIBarButtonItem!
    #endif
    
    @IBOutlet var playButton: UIBarButtonItem!
    @IBOutlet var space: UIBarButtonItem!
    @IBOutlet var trashButton: UIBarButtonItem!
    @IBOutlet var favoriteButton: UIBarButtonItem!
    
    fileprivate var playerLayer: AVPlayerLayer!
    fileprivate var isPlayingHint = false
    
    fileprivate lazy var formatIdentifier = Bundle.main.bundleIdentifier!
    fileprivate let formatVersion = "1.0"
    fileprivate lazy var ciContext = CIContext()
    
    // MARK: UIViewController / Life Cycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        livePhotoView.delegate = self
        PHPhotoLibrary.shared().register(self)
    }
    
    deinit {
        PHPhotoLibrary.shared().unregisterChangeObserver(self)
    }
    
    override func viewWillLayoutSubviews() {
        let isNavigationBarHidden = navigationController?.isNavigationBarHidden ?? false
        view.backgroundColor = isNavigationBarHidden ? .black : .white
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // 資産のメディアタイプに基づいて、適切なツールバー項目を設定します。
        #if os(iOS)
        navigationController?.isToolbarHidden = false
        navigationController?.hidesBarsOnTap = true
        if asset.mediaType == .video {
            toolbarItems = [favoriteButton, space, playButton, space, trashButton]
        } else {
            // iOSでは、静止画とライブ写真の両方を同じ方法で表示します。
            // PHLivePhotoViewは、Photosアプリケーションと同じジェスチャベースのUIを提供します。
            toolbarItems = [favoriteButton, space, trashButton]
        }
        #elseif os(tvOS)
        if asset.mediaType == .video {
            navigationItem.leftBarButtonItems = [playButton, favoriteButton, trashButton]
        } else {
            // In tvOS, PHLivePhotoView doesn't support playback gestures,
            // so add a play button for Live Photos.
            if asset.mediaSubtypes.contains(.photoLive) {
                navigationItem.leftBarButtonItems = [favoriteButton, trashButton]
            } else {
                navigationItem.leftBarButtonItems = [livePhotoPlayButton, favoriteButton, trashButton]
            }
        }
        #endif
        // ユーザーがアセットを編集できる場合は、編集ボタンを有効にします。
        editButton.isEnabled = asset.canPerform(.content)
        favoriteButton.isEnabled = asset.canPerform(.properties)
        favoriteButton.title = asset.isFavorite ? "♥︎" : "♡"
        
        // ユーザーがアセットを削除できる場合は、ゴミ箱ボタンを有効にします。
        if assetCollection != nil {
            trashButton.isEnabled = assetCollection.canPerform(.removeContent)
        } else {
            trashButton.isEnabled = asset.canPerform(.delete)
        }
        
        // viewのアップデート前にレイアウトを確定させる.
        view.layoutIfNeeded()
        updateImage()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        #if os(iOS)
        navigationController?.hidesBarsOnTap = false
        #endif
    }
    
    // MARK: UI Actions
    /// - Tag: EditAlert
    @IBAction func editAsset(_ sender: UIBarButtonItem) {
        // UIAlertControllerを使用して、編集オプションをユーザーに表示します。
        let alertController = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        #if os(iOS)
        alertController.modalPresentationStyle = .popover
        if let popoverController = alertController.popoverPresentationController {
            popoverController.barButtonItem = sender
            popoverController.permittedArrowDirections = .up
        }
        #endif
        
        // [キャンセル]アクションを追加して、何もせずにアラートを終了します。
        alertController.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: ""),
                                                style: .cancel, handler: nil))
        // PHAssetが編集操作をサポートしている場合にのみ、編集を許可します。
        if asset.canPerform(.content) {
            // いくつかのフィルタを設定するためのアクションを追加します。
            alertController.addAction(UIAlertAction(title: NSLocalizedString("Sepia Tone", comment: ""),
                                                    style: .default, handler: getFilter("CISepiaTone")))
            alertController.addAction(UIAlertAction(title: NSLocalizedString("Chrome", comment: ""),
                                                    style: .default, handler: getFilter("CIPhotoEffectChrome")))
            
            // PHAssetに対して行われた編集を元に戻すアクションを追加します。
            alertController.addAction(UIAlertAction(title: NSLocalizedString("Revert", comment: ""),
                                                    style: .default, handler: revertAsset))
        }
        // Present the UIAlertController.
        present(alertController, animated: true)
    }
    #if os(tvOS)
    @IBAction func playLivePhoto(_ sender: Any) {
        livePhotoView.startPlayback(with: .full)
    }
    #endif
    /// - Tag: PlayVideo
    @IBAction func play(_ sender: AnyObject) {
        if playerLayer != nil {
            // アプリは既にAVPlayerLayerを作成していますので、再生するように指示してください。
            playerLayer.player!.play()
        } else {
            let options = PHVideoRequestOptions()
            options.isNetworkAccessAllowed = true
            options.deliveryMode = .automatic
            options.progressHandler = { progress, _, _, _ in
                //ハンドラはバックグラウンドキューで発生する可能性があります。
                // UI作業のためにメインキューに再ディスパッチします。
                DispatchQueue.main.sync {
                    self.progressView.progress = Float(progress)
                }
            }
            //表示されたPHAssetのAVPlayerItemを要求します。
            //次に、再生するレイヤーを設定します。
            PHImageManager.default().requestPlayerItem(forVideo: asset, options: options, resultHandler: { playerItem, info in
                DispatchQueue.main.sync {
                    guard self.playerLayer == nil else { return }
                    
                    // AVPlayerItemでAVPlayerとAVPlayerLayerを作成します。
                    let player = AVPlayer(playerItem: playerItem)
                    let playerLayer = AVPlayerLayer(player: player)
                    
                    // AVPlayerLayerを設定し、ビューに追加します。
                    playerLayer.videoGravity = AVLayerVideoGravity.resizeAspect
                    playerLayer.frame = self.view.layer.bounds
                    self.view.layer.addSublayer(playerLayer)
                    
                    player.play()
                    
                    // プレーヤのレイヤーを参照でキャッシュするので、後で削除することができます。
                    self.playerLayer = playerLayer
                }
            })
        }
    }
    /// - Tag: RemoveAsset
    @IBAction func removeAsset(_ sender: AnyObject) {
        let completion = { (success: Bool, error: Error?) -> Void in
            if success {
                PHPhotoLibrary.shared().unregisterChangeObserver(self)
                DispatchQueue.main.sync {
                    _ = self.navigationController!.popViewController(animated: true)
                }
            } else {
                print("Can't remove the asset: \(String(describing: error))")
            }
        }
        if assetCollection != nil {
            // 選択したアルバムからアセットを削除します。
            PHPhotoLibrary.shared().performChanges({
                let request = PHAssetCollectionChangeRequest(for: self.assetCollection)!
                request.removeAssets([self.asset] as NSArray)
            }, completionHandler: completion)
        } else {
            // 写真ライブラリからアセットを削除します。
            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.deleteAssets([self.asset] as NSArray)
            }, completionHandler: completion)
        }
    }
    /// - Tag: MarkFavorite
    @IBAction func toggleFavorite(_ sender: UIBarButtonItem) {
        PHPhotoLibrary.shared().performChanges({
            let request = PHAssetChangeRequest(for: self.asset)
            request.isFavorite = !self.asset.isFavorite
        }, completionHandler: { success, error in
            if success {
                DispatchQueue.main.sync {
                    sender.title = self.asset.isFavorite ? "♥︎" : "♡"
                }
            } else {
                print("Can't mark the asset as a Favorite: \(String(describing: error))")
            }
        })
    }
    
    // MARK: Image display
    
    var targetSize: CGSize {
        let scale = UIScreen.main.scale
        return CGSize(width: imageView.bounds.width * scale, height: imageView.bounds.height * scale)
    }
    
    func updateImage() {
        if asset.mediaSubtypes.contains(.photoLive) {
            updateLivePhoto()
        } else {
            updateStaticImage()
        }
    }
    
    func updateLivePhoto() {
        // ライブ写真を取得するときに渡すオプションを準備します。
        let options = PHLivePhotoRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        options.progressHandler = { progress, _, _, _ in
            //ハンドラはバックグラウンドキューで発生する可能性があります。
            // UI作業のためにメインキューに再ディスパッチします。
            DispatchQueue.main.sync {
                self.progressView.progress = Float(progress)
            }
        }
        
        // デフォルトのPHImageManagerからアセットのライブ写真をリクエストします。
        PHImageManager.default().requestLivePhoto(for: asset, targetSize: targetSize, contentMode: .aspectFit, options: options,
                                                  resultHandler: { livePhoto, info in
                                                    // PhotoKitは要求を完了し、進行状況表示を非表示にします。
                                                    self.progressView.isHidden = true
                                                    
                                                    // Show the Live Photo view.
                                                    guard let livePhoto = livePhoto else { return }
                                                    
                                                    // Show the Live Photo.
                                                    self.imageView.isHidden = true
                                                    self.livePhotoView.isHidden = false
                                                    self.livePhotoView.livePhoto = livePhoto
                                                    
                                                    if !self.isPlayingHint {
                                                        //写真共有シートと同様に、ライブ写真の短い部分を再生します。
                                                        self.isPlayingHint = true
                                                        self.livePhotoView.startPlayback(with: .hint)
                                                    }
        })
    }
    
    func updateStaticImage() {
        //（写真、またはビデオプレビュー）イメージを取得するときに渡すオプションを準備します。
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        options.progressHandler = { progress, _, _, _ in
            //ハンドラはバックグラウンドキューで発生する可能性があります。
            // UI作業のためにメインキューに再ディスパッチします。
            DispatchQueue.main.sync {
                self.progressView.progress = Float(progress)
            }
        }
        
        PHImageManager.default().requestImage(for: asset, targetSize: targetSize, contentMode: .aspectFit, options: options,
                                              resultHandler: { image, _ in
                                                // PhotoKitは要求を完了したので、進行状況表示を非表示にします.
                                                self.progressView.isHidden = true
                                                
                                                // 要求が成功した場合は、画像ビューを表示します。
                                                guard let image = image else { return }
                                                
                                                // Show the image.
                                                self.livePhotoView.isHidden = true
                                                self.imageView.isHidden = false
                                                self.imageView.image = image
        })
    }
    
    // MARK: Asset editing
    
    func revertAsset(sender: UIAlertAction) {
        PHPhotoLibrary.shared().performChanges({
            let request = PHAssetChangeRequest(for: self.asset)
            request.revertAssetContentToOriginal()
        }, completionHandler: { success, error in
            if !success { print("Can't revert the asset: \(String(describing: error))") }
        })
    }
    
   
    //指定されたフィルタのフィルタアプライア関数を返します。
    //この関数をUIAlertActionオブジェクトのハンドラとして使用します。
    ///  - タグ：ApplyFilter
    func getFilter(_ filterName: String) -> (UIAlertAction) -> Void {
        func applyFilter(_: UIAlertAction) {
            // Set up a handler to handle prior edits.
            let options = PHContentEditingInputRequestOptions()
            options.canHandleAdjustmentData = {
                $0.formatIdentifier == self.formatIdentifier && $0.formatVersion == self.formatVersion
            }
            
            // 編集の準備をする。
            asset.requestContentEditingInput(with: options, completionHandler: { input, info in
                guard let input = input
                    else { fatalError("Can't get the content-editing input: \(info)") }
                
                // このハンドラはメインスレッドで実行されます。処理のためにバックグラウンドキューにディスパッチする.
                DispatchQueue.global(qos: .userInitiated).async {
                    
                    // 編集内容を説明する調整データを作成します。
                    let adjustmentData = PHAdjustmentData(formatIdentifier: self.formatIdentifier,
                                                          formatVersion: self.formatVersion,
                                                          data: filterName.data(using: .utf8)!)
                    
                    // コンテンツ編集出力を作成し、調整データを書き込みます。
                    let output = PHContentEditingOutput(contentEditingInput: input)
                    output.adjustmentData = adjustmentData
                    
                    // アセットのメディアタイプのフィルタリング機能を選択します。
                    let applyFunc: (String, PHContentEditingInput, PHContentEditingOutput, @escaping () -> Void) -> Void
                    if self.asset.mediaSubtypes.contains(.photoLive) {
                        applyFunc = self.applyLivePhotoFilter
                    } else if self.asset.mediaType == .image {
                        applyFunc = self.applyPhotoFilter
                    } else {
                        applyFunc = self.applyVideoFilter
                    }
                    
                    // Apply the filter.
                    applyFunc(filterName, input, output, {
                        // アプリがフィルタリングされた結果のレンダリングを終了したら、編集を写真ライブラリにコミットします。
                        PHPhotoLibrary.shared().performChanges({
                            let request = PHAssetChangeRequest(for: self.asset)
                            request.contentEditingOutput = output
                        }, completionHandler: { success, error in
                            if !success { print("Can't edit the asset: \(String(describing: error))") }
                        })
                    })
                }
            })
        }
        return applyFilter
    }
    
    func applyPhotoFilter(_ filterName: String, input: PHContentEditingInput, output: PHContentEditingOutput, completion: () -> Void) {
        
        // フルサイズのイメージを読み込みます。
        guard let inputImage = CIImage(contentsOf: input.fullSizeImageURL!)
            else { fatalError("Can't load the input image to edit.") }
        
        // フィルタを適用します。
        let outputImage = inputImage
            .oriented(forExifOrientation: input.fullSizeImageOrientation)
            .applyingFilter(filterName, parameters: [:])
        
        // 編集した画像をJPEGとして書き出します。
        do {
            try self.ciContext.writeJPEGRepresentation(of: outputImage,
                                                       to: output.renderedContentURL, colorSpace: inputImage.colorSpace!, options: [:])
        } catch let error {
            fatalError("Can't apply the filter to the image: \(error).")
        }
        completion()
    }
    
    func applyLivePhotoFilter(_ filterName: String, input: PHContentEditingInput, output: PHContentEditingOutput, completion: @escaping () -> Void) {
        
        //このアプリは、出力用にのみアセットをフィルタリングします。プレビューするアプリで
        //編集中にフィルターをかけ、livePhotoContextを早期に作成して再利用する
        //プレビューと最終出力の両方をレンダリングします。
        guard let livePhotoContext = PHLivePhotoEditingContext(livePhotoEditingInput: input)
            else { fatalError("Can't fetch the Live Photo to edit.") }
        
        livePhotoContext.frameProcessor = { frame, _ in
            return frame.image.applyingFilter(filterName, parameters: [:])
        }
        livePhotoContext.saveLivePhoto(to: output) { success, error in
            if success {
                completion()
            } else {
                print("Can't output the Live Photo.")
            }
        }
    }
    
    func applyVideoFilter(_ filterName: String, input: PHContentEditingInput, output: PHContentEditingOutput, completion: @escaping () -> Void) {
        // 入力から処理するAVAssetをロードします。
        guard let avAsset = input.audiovisualAsset
            else { fatalError("Can't fetch the AVAsset to edit.") }
        
        // フィルタを適用するビデオコンポジションを設定します。
        let composition = AVVideoComposition(
            asset: avAsset,
            applyingCIFiltersWithHandler: { request in
                let filtered = request.sourceImage.applyingFilter(filterName, parameters: [:])
                request.finish(with: filtered, context: nil)
        })
        
        // ビデオコンポジションを出力URLにエクスポートします。
        guard let export = AVAssetExportSession(asset: avAsset, presetName: AVAssetExportPresetHighestQuality)
            else { fatalError("Can't configure the AVAssetExportSession.") }
        export.outputFileType = AVFileType.mov
        export.outputURL = output.renderedContentURL
        export.videoComposition = composition
        export.exportAsynchronously(completionHandler: completion)
    }
}

// MARK: PHPhotoLibraryChangeObserver
extension AssetViewController: PHPhotoLibraryChangeObserver {
    func photoLibraryDidChange(_ changeInstance: PHChange) {
        // 呼び出しはバックグラウンドのキューに置かれる可能性があります。メインキューに再ディスパッチしてそれを処理します。
        DispatchQueue.main.sync {
            // 表示されたアセットに変更があるかどうかを確認します。
            guard let details = changeInstance.changeDetails(for: asset) else { return }
            
            // 更新されたアセットを取得します。
            asset = details.objectAfterChanges
            
            // アセットのコンテンツが変更された場合は、画像を更新して動画の再生をすべて停止します。
            if details.assetContentChanged {
                updateImage()
                
                playerLayer?.removeFromSuperlayer()
                playerLayer = nil
            }
        }
    }
}

// MARK: PHLivePhotoViewDelegate
extension AssetViewController: PHLivePhotoViewDelegate {
    func livePhotoView(_ livePhotoView: PHLivePhotoView, willBeginPlaybackWith playbackStyle: PHLivePhotoViewPlaybackStyle) {
        isPlayingHint = (playbackStyle == .hint)
    }
    
    func livePhotoView(_ livePhotoView: PHLivePhotoView, didEndPlaybackWith playbackStyle: PHLivePhotoViewPlaybackStyle) {
        isPlayingHint = (playbackStyle == .hint)
    }
}
