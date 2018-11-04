/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Implements the view controller for browsing photos in a grid layout.
*/

import UIKit
import Photos
import PhotosUI

private extension UICollectionView {
    func indexPathsForElements(in rect: CGRect) -> [IndexPath] {
        let allLayoutAttributes = collectionViewLayout.layoutAttributesForElements(in: rect)!
        return allLayoutAttributes.map { $0.indexPath }
    }
}

// MARK - 画像ファイル一覧画面
class AssetGridViewController: UICollectionViewController {
    
    var fetchResult: PHFetchResult<PHAsset>!
    var assetCollection: PHAssetCollection!
    var availableWidth: CGFloat = 0
    
    @IBOutlet var addButtonItem: UIBarButtonItem!
    @IBOutlet weak var collectionViewFlowLayout: UICollectionViewFlowLayout!
    
    fileprivate let imageManager = PHCachingImageManager()
    fileprivate var thumbnailSize: CGSize!
    fileprivate var previousPreheatRect = CGRect.zero
    
    // MARK: UIViewController / Life Cycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        resetCachedAssets()
        PHPhotoLibrary.shared().register(self)
        
        // Reaching this point without a segue means that this AssetGridViewController
        // became visible at app launch. As such, match the behavior of the segue from
        // the default "All Photos" view.
        if fetchResult == nil {
            let allPhotosOptions = PHFetchOptions()
            allPhotosOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
            fetchResult = PHAsset.fetchAssets(with: allPhotosOptions)
        }
    }
    
    deinit {
        PHPhotoLibrary.shared().unregisterChangeObserver(self)
    }
    
    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        let width = view.bounds.inset(by: view.safeAreaInsets).width
        // 使用可能な幅が変更された場合はアイテムサイズを調整します。
        if availableWidth != width {
            availableWidth = width
            let columnCount = (availableWidth / 80).rounded(.towardZero)
            let itemLength = (availableWidth - columnCount - 1) / columnCount
            collectionViewFlowLayout.itemSize = CGSize(width: itemLength, height: itemLength)
        }
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        // PHCachingImageManagerから要求するサムネイルのサイズを決定します。
        let scale = UIScreen.main.scale
        let cellSize = collectionViewFlowLayout.itemSize
        thumbnailSize = CGSize(width: cellSize.width * scale, height: cellSize.height * scale)
        
        // アセットコレクションでコンテンツの追加がサポートされている場合は、ナビゲーションバーにボタンを追加します。
        if assetCollection == nil || assetCollection.canPerform(.addContent) {
            navigationItem.rightBarButtonItem = addButtonItem
        } else {
            navigationItem.rightBarButtonItem = nil
        }
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        updateCachedAssets()
    }
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        guard let destination = segue.destination as? AssetViewController else { fatalError("Unexpected view controller for segue") }
        guard let collectionViewCell = sender as? UICollectionViewCell else { fatalError("Unexpected sender for segue") }
        
        let indexPath = collectionView.indexPath(for: collectionViewCell)!
        destination.asset = fetchResult.object(at: indexPath.item)
        destination.assetCollection = assetCollection
    }
    
    // MARK: UICollectionView
    
    override func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return fetchResult.count
    }
    /// - Tag: PopulateCell
    override func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let asset = fetchResult.object(at: indexPath.item)
        // Dequeue a GridViewCell.
        guard let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "GridViewCell", for: indexPath) as? GridViewCell
            else { fatalError("Unexpected cell in collection view") }
        
        // Add a badge to the cell if the PHAsset represents a Live Photo.
        if asset.mediaSubtypes.contains(.photoLive) {
            cell.livePhotoBadgeImage = PHLivePhotoView.livePhotoBadgeImage(options: .overContent)
        }
        
        // PHCachingImageManagerからアセットのイメージをリクエストします。
        cell.representedAssetIdentifier = asset.localIdentifier
        imageManager.requestImage(for: asset, targetSize: thumbnailSize, contentMode: .aspectFill, options: nil, resultHandler: { image, _ in
            // UIKitはハンドラの起動時間によってこのセルをリサイクルしている可能性があります。
            //同じアセットを表示している場合にのみ、セルのサムネイルイメージを設定します。
            if cell.representedAssetIdentifier == asset.localIdentifier {
                cell.thumbnailImage = image
            }
        })
        return cell
    }
    
    // MARK: UIScrollView
    
    override func scrollViewDidScroll(_ scrollView: UIScrollView) {
        updateCachedAssets()
    }
    
    // MARK: Asset Caching
    
    fileprivate func resetCachedAssets() {
        imageManager.stopCachingImagesForAllAssets()
        previousPreheatRect = .zero
    }
    /// - Tag: UpdateAssets
    fileprivate func updateCachedAssets() {
        // ビューが表示されている場合のみ更新します。
        guard isViewLoaded && view.window != nil else { return }
        
        // 前もって準備しておくウィンドウは、表示されている矩形の高さの2倍です。
        let visibleRect = CGRect(origin: collectionView!.contentOffset, size: collectionView!.bounds.size)
        let preheatRect = visibleRect.insetBy(dx: 0, dy: -0.5 * visibleRect.height)
        
        // 可視領域が最後の予熱領域と大きく異なる場合にのみ更新します。
        let delta = abs(preheatRect.midY - previousPreheatRect.midY)
        guard delta > view.bounds.height / 3 else { return }
        
        // キャッシュを開始および停止するアセットを計算します。
        let (addedRects, removedRects) = differencesBetweenRects(previousPreheatRect, preheatRect)
        let addedAssets = addedRects
            .flatMap { rect in collectionView!.indexPathsForElements(in: rect) }
            .map { indexPath in fetchResult.object(at: indexPath.item) }
        let removedAssets = removedRects
            .flatMap { rect in collectionView!.indexPathsForElements(in: rect) }
            .map { indexPath in fetchResult.object(at: indexPath.item) }
        
        // PHCachingImageManagerがキャッシングしているアセットを更新します。
        imageManager.startCachingImages(for: addedAssets,
                                        targetSize: thumbnailSize, contentMode: .aspectFill, options: nil)
        imageManager.stopCachingImages(for: removedAssets,
                                       targetSize: thumbnailSize, contentMode: .aspectFill, options: nil)
        // 将来の比較のために計算された矩形を格納します。
        previousPreheatRect = preheatRect
    }
    
    fileprivate func differencesBetweenRects(_ old: CGRect, _ new: CGRect) -> (added: [CGRect], removed: [CGRect]) {
        if old.intersects(new) {
            var added = [CGRect]()
            if new.maxY > old.maxY {
                added += [CGRect(x: new.origin.x, y: old.maxY,
                                 width: new.width, height: new.maxY - old.maxY)]
            }
            if old.minY > new.minY {
                added += [CGRect(x: new.origin.x, y: new.minY,
                                 width: new.width, height: old.minY - new.minY)]
            }
            var removed = [CGRect]()
            if new.maxY < old.maxY {
                removed += [CGRect(x: new.origin.x, y: new.maxY,
                                   width: new.width, height: old.maxY - new.maxY)]
            }
            if old.minY < new.minY {
                removed += [CGRect(x: new.origin.x, y: old.minY,
                                   width: new.width, height: new.minY - old.minY)]
            }
            return (added, removed)
        } else {
            return ([new], [old])
        }
    }
    
    // MARK: UI Actions
    /// - Tag: AddAsset
    @IBAction func addAsset(_ sender: AnyObject?) {
        
        // ランダムな単色とランダムな向きのダミー画像を作成します。
        let size = (arc4random_uniform(2) == 0) ?
            CGSize(width: 400, height: 300) :
            CGSize(width: 300, height: 400)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { context in
            UIColor(hue: CGFloat(arc4random_uniform(100)) / 100,
                    saturation: 1, brightness: 1, alpha: 1).setFill()
            context.fill(context.format.bounds)
        }
        // 写真ライブラリにアセットを追加します。
        PHPhotoLibrary.shared().performChanges({
            let creationRequest = PHAssetChangeRequest.creationRequestForAsset(from: image)
            if let assetCollection = self.assetCollection {
                let addAssetRequest = PHAssetCollectionChangeRequest(for: assetCollection)
                addAssetRequest?.addAssets([creationRequest.placeholderForCreatedAsset!] as NSArray)
            }
        }, completionHandler: {success, error in
            if !success { print("Error creating the asset: \(String(describing: error))") }
        })
    }
    
}

// MARK: PHPhotoLibraryChangeObserver
extension AssetGridViewController: PHPhotoLibraryChangeObserver {
    func photoLibraryDidChange(_ changeInstance: PHChange) {
        
        guard let changes = changeInstance.changeDetails(for: fetchResult)
            else { return }
        
        // Change notifications may originate from a background queue.
        // As such, re-dispatch execution to the main queue before acting
        // on the change, so you can update the UI.
        DispatchQueue.main.sync {
            // Hang on to the new fetch result.
            fetchResult = changes.fetchResultAfterChanges
            // If we have incremental changes, animate them in the collection view.
            if changes.hasIncrementalChanges {
                guard let collectionView = self.collectionView else { fatalError() }
                // Handle removals, insertions, and moves in a batch update.
                collectionView.performBatchUpdates({
                    if let removed = changes.removedIndexes, !removed.isEmpty {
                        collectionView.deleteItems(at: removed.map({ IndexPath(item: $0, section: 0) }))
                    }
                    if let inserted = changes.insertedIndexes, !inserted.isEmpty {
                        collectionView.insertItems(at: inserted.map({ IndexPath(item: $0, section: 0) }))
                    }
                    changes.enumerateMoves { fromIndex, toIndex in
                        collectionView.moveItem(at: IndexPath(item: fromIndex, section: 0),
                                                to: IndexPath(item: toIndex, section: 0))
                    }
                })
                // We are reloading items after the batch update since `PHFetchResultChangeDetails.changedIndexes` refers to
                // items in the *after* state and not the *before* state as expected by `performBatchUpdates(_:completion:)`.
                if let changed = changes.changedIndexes, !changed.isEmpty {
                    collectionView.reloadItems(at: changed.map({ IndexPath(item: $0, section: 0) }))
                }
            } else {
                // Reload the collection view if incremental changes are not available.
                collectionView.reloadData()
            }
            resetCachedAssets()
        }
    }
}

