# SPDX-License-Identifier: GPL-2.0-or-later
"""Measured image-feature registration for physical UV projection bakes."""
import numpy as np


def fit(anchors):
    target=np.asarray([a['target'] for a in anchors],float)
    source=np.asarray([a['source'] for a in anchors],float)
    if target.shape!=source.shape or target.ndim!=2 or target.shape[1]!=2 or len(target)<3:
        raise ValueError('Registration needs at least three paired image UV anchors')
    if not np.isfinite(target).all() or not np.isfinite(source).all():raise ValueError('Invalid registration anchors')
    square=np.sum((target[:,None]-target[None,:])**2,axis=-1)
    kernel=square*np.log(np.maximum(square,1e-20))
    affine=np.column_stack((np.ones(len(target)),target))
    matrix=np.block([[kernel,affine],[affine.T,np.zeros((3,3))]])
    if len(np.unique(target,axis=0))!=len(target) or np.linalg.matrix_rank(affine)<3:
        raise ValueError('Registration anchors must be unique and span the image plane')
    try:coefficients=np.linalg.solve(matrix,np.concatenate((source,np.zeros((3,2)))))
    except np.linalg.LinAlgError as error:raise ValueError('Singular registration anchors') from error
    features=np.asarray([a['target'] for a in anchors if a.get('name') not in (None,'canvas')],float)
    region=(features.min(axis=0)-.03,features.max(axis=0)+.03) if len(features) else None
    return target,coefficients,region


def project(points,transform):
    target,coefficients,region=transform
    points=np.asarray(points,float)
    square=np.sum((points[...,None,:]-target)**2,axis=-1)
    basis=np.concatenate((square*np.log(np.maximum(square,1e-20)),np.ones((*points.shape[:-1],1)),points),axis=-1)
    with np.errstate(divide='ignore',invalid='ignore'):
        warped=basis@coefficients
    if not np.isfinite(warped).all():raise ValueError('Nonfinite registered image coordinates')
    if region is not None:
        low,high=region
        distance=np.maximum(np.maximum(low-points,points-high),0).max(axis=-1)
        # A short fade can fold a displaced eyelid back onto itself and paint
        # its brow twice. Spread the falloff beyond the measured face features.
        amount=np.clip(1-distance/.15,0,1)
        amount=amount*amount*(3-2*amount)
        warped=points+(warped-points)*amount[...,None]
    return warped


def validate(transform):
    """Reject projections that reverse or collapse any sampled image region."""
    resolution=201
    grid=np.stack(np.meshgrid(np.linspace(0,1,resolution),
                              np.linspace(0,1,resolution)),axis=-1)
    mapped=project(grid,transform)
    dx=np.gradient(mapped,axis=1)*(resolution-1)
    dy=np.gradient(mapped,axis=0)*(resolution-1)
    determinant=dx[:,:,0]*dy[:,:,1]-dx[:,:,1]*dy[:,:,0]
    minimum=float(determinant.min())
    if not np.isfinite(determinant).all() or minimum<=0:
        raise ValueError('Face registration folds or collapses the image: minimum Jacobian '+str(minimum))
    return dict(resolution=resolution,minimum_jacobian=minimum,folds=0)
