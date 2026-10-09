"""Offline product-photo processing. Originals are never overwritten."""
import argparse
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageOps


def prepare(source, output, white=False, shadow=True):
    Image.MAX_IMAGE_PIXELS = 60_000_000
    with Image.open(source) as opened:
        image = ImageOps.exif_transpose(opened).convert('RGBA')
    image.thumbnail((3000, 3000), Image.Resampling.LANCZOS)
    if white:
        model = Path.home() / '.rembg/models/u2net/u2net.onnx'
        if not model.is_file():
            raise ValueError('本地抠图模型未安装，请先完成修图环境部署。')
        from rembg import new_session, remove
        session = new_session('u2net', providers=['CPUExecutionProvider'])
        mask = remove(image, session=session).getchannel('A')
        if mask.getextrema()[1] < 32:
            raise ValueError('没有识别到物品，请换用清晰照片或仅统一尺寸。')
        image.putalpha(mask)
        box = mask.point(lambda a: 255 if a > 32 else 0).getbbox()
    else:
        pixels = np.asarray(image)
        alpha = pixels[:, :, 3]
        if np.any(alpha < 250):
            box = image.getchannel('A').point(lambda a: 255 if a > 32 else 0).getbbox()
        else:
            # Crop only on an already white background; a scene photo keeps its frame.
            edges = np.concatenate([pixels[0, :, :3], pixels[-1, :, :3], pixels[:, 0, :3], pixels[:, -1, :3]])
            if np.mean(np.min(edges, axis=1) > 240) > .92:
                ys, xs = np.where(np.min(pixels[:, :, :3], axis=2) < 225)
                box = (xs.min(), ys.min(), xs.max()+1, ys.max()+1) if len(xs) else None
            else:
                box = (0, 0, image.width, image.height)
    if box is None:
        raise ValueError('图片为空或没有可见物品。')
    left, top, right, bottom = box
    padding = round(max(right-left, bottom-top) * .1)
    crop_left, crop_top = max(0, left-padding), max(0, top-padding)
    image = image.crop((crop_left, crop_top, min(image.width, right+padding), min(image.height, bottom+padding)))
    left, right = left-crop_left, right-crop_left
    top, bottom = top-crop_top, bottom-crop_top
    scale = 840 / max(right-left, bottom-top)
    resized = image.resize((max(1, round(image.width*scale)), max(1, round(image.height*scale))), Image.Resampling.LANCZOS)
    x, y = round(512-(left+right)*scale/2), round(512-(top+bottom)*scale/2)
    canvas = Image.new('RGBA', (1024, 1024), 'white')
    if white and shadow:
        layer = Image.new('RGBA', canvas.size)
        width = min(720, max(100, (right-left)*scale*.8))
        floor = 512 + (bottom-top)*scale/2
        ImageDraw.Draw(layer).ellipse((512-width/2, floor-12, 512+width/2, floor+24), fill=(0, 0, 0, 38))
        canvas = Image.alpha_composite(canvas, layer.filter(ImageFilter.GaussianBlur(18)))
    canvas.alpha_composite(resized, (x, y))
    canvas.convert('RGB').save(output, 'PNG', optimize=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('source', type=Path)
    parser.add_argument('output', type=Path)
    parser.add_argument('--white', action='store_true')
    parser.add_argument('--no-shadow', action='store_true')
    args = parser.parse_args()
    prepare(args.source, args.output, args.white, not args.no_shadow)
